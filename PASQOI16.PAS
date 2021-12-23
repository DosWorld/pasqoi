{$F+,A-,S-,I-,R-,O-}
UNIT pasqoi16;

INTERFACE

{
QOI - The "Quite OK Image" format for fast, lossless image compression

Dominic Szablewski - https://phoboslab.org


-- LICENSE: The MIT License(MIT)

Copyright(c) 2021 Dominic Szablewski
Copyright(c) 2021 Viacheslav Komenda

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files(the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and / or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions :
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


-- About

QOI encodes and decodes images in a lossless format. An encoded QOI image is
usually around 10--30% larger than a decently optimized PNG image.

QOI outperforms simpler PNG encoders in compression ratio and performance. QOI
images are typically 20% smaller than PNGs written with stbi_image. Encoding is 
25-50x faster and decoding is 3-4x faster than stbi_image or libpng.

-- Data Format

A QOI file has a 14 byte header, followed by any number of data "chunks" and an
8-byte end marker.

record
        magic      : array [0..3] of char;
        width      : longint;
        height     : longint;
        channels   : byte;
        colorspace : byte;
end;

magic - magic bytes "qoif"
width - image width in pixels (BE)
height - image height in pixels (BE)
channels -  3 = RGB, 4 = RGBA
colorspace - 0 = sRGB with linear alpha, 1 = all channels linear

The decoder and encoder start with (r: 0, g: 0, b: 0, a: 255) as the previous
pixel value. Pixels are either encoded as
 - a run of the previous pixel
 - an index into an array of previously seen pixels
 - a difference to the previous pixel value in r,g,b
 - full r,g,b or r,g,b,a values

The color channels are assumed to not be premultiplied with the alpha channel 
("un-premultiplied alpha").

A running array[64] (zero-initialized) of previously seen pixel values is 
maintained by the encoder and decoder. Each pixel that is seen by the encoder
and decoder is put into this array at the position formed by a hash function of
the color value. In the encoder, if the pixel value at the index matches the
current pixel, this index position is written to the stream as QOI_OP_INDEX. 
The hash function for the index is:

        index_position = (r * 3 + g * 5 + b * 7 + a * 11) % 64

Each chunk starts with a 2- or 8-bit tag, followed by a number of data bits. The 
bit length of chunks is divisible by 8 - i.e. all chunks are byte aligned. All 
values encoded in these data bits have the most significant bit on the left.

The 8-bit tags have precedence over the 2-bit tags. A decoder must check for the
presence of an 8-bit tag first.

The byte stream's end is marked with 7 0x00 bytes followed a single 0x01 byte.

The possible chunks are:


.- QOI_OP_INDEX ----------.
|         Byte[0]         |
|  7  6  5  4  3  2  1  0 |
|-------+-----------------|
|  0  0 |     index       |
`-------------------------`
2-bit tag b00
6-bit index into the color index array: 0..63

A valid encoder must not issue 7 or more consecutive QOI_OP_INDEX chunks to the
index 0, to avoid confusion with the 8 byte end marker. 


.- QOI_OP_DIFF -----------. 
|         Byte[0]         |
|  7  6  5  4  3  2  1  0 |
|-------+-----+-----+-----|
|  0  1 |  dr |  dg |  db |
`-------------------------`
2-bit tag b01
2-bit   red channel difference from the previous pixel between -2..1
2-bit green channel difference from the previous pixel between -2..1
2-bit  blue channel difference from the previous pixel between -2..1

The difference to the current channel values are using a wraparound operation, 
so "1 - 2" will result in 255, while "255 + 1" will result in 0.

Values are stored as unsigned integers with a bias of 2. E.g. -2 is stored as 
0 (b00). 1 is stored as 3 (b11).


.- QOI_OP_LUMA -------------------------------------. 
|         Byte[0]         |         Byte[1]         |
|  7  6  5  4  3  2  1  0 |  7  6  5  4  3  2  1  0 |
|-------+-----------------+-------------+-----------|
|  1  0 |  green diff     |   dr - dg   |  db - dg  |
`---------------------------------------------------`
2-bit tag b10
6-bit green channel difference from the previous pixel -32..31
4-bit   red channel difference minus green channel difference -8..7
4-bit  blue channel difference minus green channel difference -8..7

The green channel is used to indicate the general direction of change and is 
encoded in 6 bits. The red and green channels (dr and db) base their diffs off
of the green channel difference and are encoded in 4 bits. I.e.:
        dr_dg = (last_px.r - cur_px.r) - (last_px.g - cur_px.g)
        db_dg = (last_px.b - cur_px.b) - (last_px.g - cur_px.g)

The difference to the current channel values are using a wraparound operation, 
so "10 - 13" will result in 253, while "250 + 7" will result in 1.

Values are stored as unsigned integers with a bias of 32 for the green channel 
and a bias of 8 for the red and blue channel.


.- QOI_OP_RUN ------------.
|         Byte[0]         |
|  7  6  5  4  3  2  1  0 |
|-------+-----------------|
|  1  1 |       run       |
`-------------------------`
2-bit tag b11
6-bit run-length repeating the previous pixel: 1..62

The run-length is stored with a bias of 1. Note that the run-lengths 63 and 64 
(b111110 and b111111) are illegal as they are occupied by the QOI_OP_RGB and 
QOI_OP_RGBA tags.


.- QOI_OP_RGB ------------------------------------------.
|         Byte[0]         | Byte[1] | Byte[2] | Byte[3] |
|  7  6  5  4  3  2  1  0 | 7 .. 0  | 7 .. 0  | 7 .. 0  |
|-------------------------+---------+---------+---------|
|  1  1  1  1  1  1  1  0 |   red   |  green  |  blue   |
`-------------------------------------------------------`
8-bit tag b11111110
8-bit   red channel value
8-bit green channel value
8-bit  blue channel value


.- QOI_OP_RGBA ---------------------------------------------------.
|         Byte[0]         | Byte[1] | Byte[2] | Byte[3] | Byte[4] |
|  7  6  5  4  3  2  1  0 | 7 .. 0  | 7 .. 0  | 7 .. 0  | 7 .. 0  |
|-------------------------+---------+---------+---------+---------|
|  1  1  1  1  1  1  1  1 |   red   |  green  |  blue   |  alpha  |
`-----------------------------------------------------------------`
8-bit tag b11111111
8-bit   red channel value
8-bit green channel value
8-bit  blue channel value
8-bit alpha channel value

The byte stream is padded at the end with 8 zero bytes. Since the longest legal 
chunk is 5 bytes (QOI_OP_RGBA), with this padding it is possible to check for an
overrun only once per decode loop iteration. These 0x00 bytes also mark the end
of the data stream, as an encoder should never produce 8 consecutive zero bytes
within the stream.
}

CONST

QOI_SRGB      = 0;
QOI_LINEAR    = 1;

QOI_MAGIC     = $716f6966;
QOI_HEADER_SIZE = 14;

{ 2GB is the max file size that this implementation can safely handle. We guard
against anything larger than that, assuming the worst case with 5 bytes per 
pixel, rounded down to a nice clean value. 400 million pixels ought to be 
enough for anybody. }

TYPE

PQOI_DESC = ^TQOI_DESC;
TQOI_DESC = RECORD
        magic      : LONGINT;
        width      : LONGINT;
        height     : LONGINT;
        channels   : BYTE;
        colorspace : BYTE;
END;

{$F+}
QOI_IO_PROC = PROCEDURE(usr_ctx : POINTER; desc : PQOI_DESC; VAR b; size : INTEGER; VAR iocount : INTEGER);

FUNCTION qoi_decode(usr_ctx : POINTER; qReader, qWriter : QOI_IO_PROC; desc : PQOI_DESC; channels : INTEGER) : BOOLEAN;
FUNCTION qoi_encode(usr_ctx : POINTER; qReader, qWriter : QOI_IO_PROC; desc : PQOI_DESC) : BOOLEAN;

IMPLEMENTATION

CONST

QOI_OP_INDEX  = $00; { 00xxxxxx }
QOI_OP_DIFF   = $40; { 01xxxxxx }
QOI_OP_LUMA   = $80; { 10xxxxxx }
QOI_OP_RUN    = $c0; { 11xxxxxx }
QOI_OP_RGB    = $fe; { 11111110 }
QOI_OP_RGBA   = $ff; { 11111111 }
QOI_MASK_2    = $c0; { 11000000 }

QOI_PIXELS_MAX : LONGINT = $17D78400;

qoi_padding : ARRAY[0..7] OF BYTE = (0,0,0,0,0,0,0,1);

BUF_SIZE = 4 * 1024;

TYPE

PQOI_RGBA = ^TQOI_RGBA;
TQOI_RGBA = RECORD
        r, g, b, a : BYTE;
END;

PLONGINT = ^LONGINT;
IOBUF = ARRAY[0 .. BUF_SIZE - 1] OF BYTE;

FUNCTION qoi_color_hash(VAR c : TQOI_RGBA) : INTEGER;
BEGIN
        qoi_color_hash := (INTEGER(c.r) * 3 +
                INTEGER(c.g) * 5 +
                INTEGER(c.b) * 7 +
                INTEGER(c.a) * 11) and $3f;
END;

PROCEDURE qoi_write_32(VAR bytes : IOBUF; VAR p : INTEGER; v : LONGINT);
BEGIN
        bytes[p] := (v shr 24) and $ff;
        inc(p);
        bytes[p] := (v shr 16) and $ff;
        inc(p);
        bytes[p] := (v shr 8) and $ff;
        inc(p);
        bytes[p] := v and $ff;
        inc(p);
END;

FUNCTION qoi_read_32(VAR bytes : IOBUF; VAR p : INTEGER):LONGINT;
VAR
        a, b, c, d : LONGINT;
BEGIN
        a := bytes[p] and $ff;
        inc(p);
        b := bytes[p] and $ff;
        inc(p);
        c := bytes[p] and $ff;
        inc(p);
        d := bytes[p] and $ff;
        inc(p);
        qoi_read_32 := (a shl 24) or (b shl 16) or (c shl 8) or d;
END;

FUNCTION is_valid_header(desc : PQOI_DESC) : BOOLEAN;
BEGIN
        is_valid_header := FALSE;
        IF (desc <> nil) THEN BEGIN
                is_valid_header := (desc^.width <> 0) and (desc^.height <> 0) and
                        (desc^.channels in [3, 4]) and
                        (desc^.height < (QOI_PIXELS_MAX div desc^.width));
        END;
END;

FUNCTION qoi_encode(usr_ctx : POINTER; qReader, qWriter : QOI_IO_PROC; desc : PQOI_DESC) : BOOLEAN;
VAR
        p           : INTEGER;
        i, run      : INTEGER;
        px_len      : LONGINT;
        px_pos      : INTEGER;
        channels    : INTEGER;
        index       : ARRAY [0..63] OF TQOI_RGBA;
        px, px_prev : TQOI_RGBA;
        index_pos   : INTEGER;

        vr, vg, vb  : INTEGER;
        vg_r, vg_b  : INTEGER;

        bytes  : IOBUF;
        pixels : IOBUF;
        obuf   : INTEGER;
        inbuf  : INTEGER;

        FUNCTION NextByte:BYTE;
        VAR
                r : BYTE;
        BEGIN
                IF px_pos = inbuf THEN BEGIN
                        qReader(usr_ctx, desc, pixels, BUF_SIZE, inbuf);
                        px_pos := 0;
                END;
                r := bytes[px_pos];
                Inc(px_pos);
                NextByte := r;
        END;

        PROCEDURE WriteByte(b : BYTE);
        BEGIN
                IF p = BUF_SIZE THEN BEGIN
                        qWriter(usr_ctx, desc, bytes, BUF_SIZE, obuf);
                        p := 0;
                END;
                bytes[p] := b;
                Inc(p);
        END;

BEGIN
        qoi_encode := FALSE;

        IF not is_valid_header(desc) THEN EXIT;

        p := 0;
        obuf := 0;

        qoi_write_32(bytes, p, QOI_MAGIC);
        qoi_write_32(bytes, p, desc^.width);
        qoi_write_32(bytes, p, desc^.height);

        WriteByte(desc^.channels);
        WriteByte(desc^.colorspace);

        FillChar(index, SizeOf(index), #0);

        run := 0;
        px_prev.r := 0;
        px_prev.g := 0;
        px_prev.b := 0;
        px_prev.a := 255;

        px := px_prev;
        
        px_len := desc^.width * desc^.height;
        channels := desc^.channels;

        qReader(usr_ctx, desc, pixels, BUF_SIZE, inbuf);
        px_pos := 0;
        WHILE px_len <> 0 DO BEGIN
                px.r := NextByte;
                px.g := NextByte;
                px.b := NextByte;
                IF channels = 4 THEN px.a := NextByte;

                IF plongint(@px)^ = plongint(@px_prev)^ THEN BEGIN
                        Inc(run);
                        IF (run = 62) or (px_len = 1) THEN BEGIN
                                WriteByte(QOI_OP_RUN or (run - 1));
                                run := 0;
                        END;
                END ELSE BEGIN
                        IF run > 0 THEN BEGIN
                                WriteByte(QOI_OP_RUN or (run - 1));
                                run := 0;
                        END;

                        index_pos := qoi_color_hash(px);

                        IF plongint(@index[index_pos])^ = plongint(@px)^ THEN BEGIN
                                WriteByte(QOI_OP_INDEX or index_pos);
                        END ELSE BEGIN
                                plongint(@index[index_pos])^ := plongint(@px)^;

                                IF px.a = px_prev.a THEN BEGIN
                                        vr := px.r - px_prev.r;
                                        vg := px.g - px_prev.g;
                                        vb := px.b - px_prev.b;

                                        vg_r := vr - vg;
                                        vg_b := vb - vg;

                                        IF (vr > -3) and (vr < 2) and
                                           (vg > -3) and (vg < 2) and
                                           (vb > -3) and (vb < 2) THEN BEGIN
                                                WriteByte(QOI_OP_DIFF or
                                                        ((vr + 2) shl 4) or
                                                        ((vg + 2) shl 2) or
                                                        (vb + 2));
                                        END ELSE IF (vg_r >  -9) and (vg_r <  8) and
                                                (vg   > -33) and (vg   < 32) and
                                                (vg_b >  -9) and (vg_b <  8) THEN BEGIN
                                                WriteByte(QOI_OP_LUMA or (vg + 32));
                                                WriteByte(((vg_r + 8) shl 4) or (vg_b +  8));
                                        END ELSE BEGIN
                                                IF p + 4 >= BUF_SIZE THEN BEGIN
                                                        qWriter(usr_ctx, desc, bytes, p, obuf);
                                                        p := 0;
                                                END;
                                                bytes[p] := QOI_OP_RGB;
                                                Inc(p);
                                                bytes[p] := px.r;
                                                Inc(p);
                                                bytes[p] := px.g;
                                                Inc(p);
                                                bytes[p] := px.b;
                                                Inc(p);
                                        END;
                                END ELSE BEGIN
                                        IF p + 5 >= BUF_SIZE THEN BEGIN
                                                qWriter(usr_ctx, desc, bytes, p, obuf);
                                                p := 0;
                                        END;
                                        bytes[p] := QOI_OP_RGBA;
                                        Inc(p);
                                        plongint(@bytes[p])^ := plongint(@px)^;
                                        Inc(p, 4);
                                END;
                        END;
                END;
                plongint(@px_prev)^ := plongint(@px)^;
                Dec(px_len);
        END;

        IF p <> 0 THEN qWriter(usr_ctx, desc, bytes, p, inbuf);
        qWriter(usr_ctx, desc, qoi_padding, SizeOf(qoi_padding), inbuf);

        qoi_encode := TRUE;
END;

FUNCTION qoi_decode(usr_ctx : POINTER; qReader, qWriter : QOI_IO_PROC; desc : PQOI_DESC; channels : INTEGER) : BOOLEAN;
VAR
        index  : ARRAY [0..63] OF TQOI_RGBA;
        px     : TQOI_RGBA;
        px_len : LONGINT;
        px_pos : INTEGER;
        run    : INTEGER;
        vg     : INTEGER;
        b1, b2 : BYTE;

        bytes  : IOBUF;
        pixels : IOBUF;
        p      : INTEGER;
        inbuf  : INTEGER;
        obuf   : INTEGER;

        FUNCTION NextByte:BYTE;
        BEGIN
                IF p = inbuf THEN BEGIN
                        qReader(usr_ctx, desc, bytes, BUF_SIZE, inbuf);
                        p := 0;
                END;
                NextByte := bytes[p];
                Inc(p);
        END;

BEGIN
        qoi_decode := FALSE;
        p := 0;
        run := 0;

        IF (desc = nil) or (not channels in [0, 3, 4]) THEN EXIT;

        qReader(usr_ctx, desc, bytes, BUF_SIZE, inbuf);

        desc^.magic := qoi_read_32(bytes, p);
        desc^.width := qoi_read_32(bytes, p);
        desc^.height := qoi_read_32(bytes, p);
        desc^.channels := NextByte;
        desc^.colorspace := NextByte;

        IF not is_valid_header(desc) THEN EXIT;

        IF channels = 0 THEN channels := desc^.channels;

        FillChar(index, SizeOf(index), #0);

        px.r := 0;
        px.g := 0;
        px.b := 0;
        px.a := 255;

        px_pos := 0;
        px_len := desc^.width * desc^.height;
        WHILE px_len <> 0 DO BEGIN
                IF run <> 0 THEN Dec(run)
                ELSE BEGIN
                        b1 := NextByte;
                        IF b1 = QOI_OP_RGB THEN BEGIN
                                px.r := NextByte;
                                px.g := NextByte;
                                px.b := NextByte;
                        END ELSE IF b1 = QOI_OP_RGBA THEN BEGIN
                                px.r := NextByte;
                                px.g := NextByte;
                                px.b := NextByte;
                                px.a := NextByte;
                        END ELSE IF (b1 and QOI_MASK_2) = QOI_OP_INDEX THEN BEGIN
                                plongint(@px)^ := plongint(@index[b1])^;
                        END ELSE IF (b1 and QOI_MASK_2) = QOI_OP_DIFF THEN BEGIN
                                inc(px.r, ((b1 shr 4) and $03) - 2);
                                inc(px.g, ((b1 shr 2) and $03) - 2);
                                inc(px.b, ( b1        and $03) - 2);
                        END ELSE IF (b1 and QOI_MASK_2) = QOI_OP_LUMA THEN BEGIN
                                b2 := NextByte;
                                vg := (b1 and $3f) - 32;
                                inc(px.r, vg - 8 + ((b2 shr 4) and $0f));
                                inc(px.g, vg);
                                inc(px.b, vg - 8 +  (b2 and $0f));
                        END ELSE IF (b1 and QOI_MASK_2) = QOI_OP_RUN THEN BEGIN
                                run := b1 and $3f;
                        END;

                        plongint(@index[qoi_color_hash(px)])^ := plongint(@px)^;
                END;

                IF channels = 4 THEN BEGIN
                        IF px_pos >= BUF_SIZE - 4 THEN BEGIN
                                qWriter(usr_ctx, desc, pixels, px_pos, obuf);
                                px_pos := 0;
                        END;
                        plongint(@pixels[px_pos])^ := plongint(@px)^;
                        Inc(px_pos, 4);
                END ELSE BEGIN
                        IF px_pos >= BUF_SIZE - 3 THEN BEGIN
                                qWriter(usr_ctx, desc, pixels, px_pos, obuf);
                                px_pos := 0;
                        END;
                        pixels[px_pos] := px.r;
                        Inc(px_pos);
                        pixels[px_pos] := px.g;
                        Inc(px_pos);
                        pixels[px_pos] := px.b;
                        Inc(px_pos);
                END;
                Dec(px_len);
        END;

        IF px_pos <> 0 THEN qWriter(usr_ctx, desc, pixels, px_pos, obuf);
        qoi_decode := TRUE;
END;

END.
