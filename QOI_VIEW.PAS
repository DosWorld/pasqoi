{$F+,S-,I-,R-,O-,F+,A-}
USES PASQOI;

TYPE
PMCTX = ^TMCTX;
TMCTX = RECORD
        f   : File;
        inited : boolean;
        ofs : word;
        width : word;
        y :word;
        x :word;
END;

PROCEDURE TextMode;ASSEMBLER;
ASM
        MOV  AX, 3
        INT  $10
END;

PROCEDURE GraphMode;ASSEMBLER;
ASM
        MOV  AX, $13
        INT  $10
END;

PROCEDURE qread(usr_ctx : POINTER; desc : PQOI_DESC; VAR b; size : WORD; VAR iocount : WORD);far;
VAR
        i   : INTEGER;
BEGIN
        {$I-}
        BlockRead(PMCTX(usr_ctx)^.f, b, size, iocount);
        i := ioResult;
        {$I+}
        IF i <> 0 THEN iocount := 0;
END;

PROCEDURE qwrite(usr_ctx : POINTER; desc : PQOI_DESC; VAR b; size : WORD; VAR iocount : WORD);far;
VAR
        ctx : PMCTX;
        pc   : PCHAR;
        bank : integer;
        c    : integer;
BEGIN
        pc := @b;
        iocount := size;
        ctx := PMCTX(usr_ctx);
        IF NOT ctx^.inited THEN BEGIN
                ctx^.width := desc^.width;
                ctx^.x := 0;
                ctx^.y := 0;
                ctx^.ofs := 0;
                ctx^.inited := true;
        END;
        WHILE size <> 0 DO BEGIN
                IF ctx^.width = 0 THEN BEGIN
                        ctx^.width := desc^.width;
                        inc(ctx^.y);
                        ctx^.x := 0;
                        ctx^.ofs := ctx^.y * 320;
                END;
                if (ctx^.x < 320) and (ctx^.y < 200) then begin
                        c := (ord(pc[0]) and $ff + ord(pc[1]) and $ff + ord(pc[3]) and $ff) div 3;
{                        if c > 127 then c := 15 else c := 0; }
                        mem[segA000:ctx^.ofs] := c;
                end;
                inc(pc, 3);
                inc(ctx^.x);
                inc(ctx^.ofs);
                Dec(ctx^.width);
                Dec(size, 3);
        END;
END;

VAR
        ctx  : TMCTX;
        i    : INTEGER;
        desc : TQOI_DESC;
        r    : BOOLEAN;
BEGIN
        IF ParamCount <> 1 THEN BEGIN
                WriteLn('Example of QOI-file viewer.');
                WriteLn;
                WriteLn('Usage:');
                WriteLn;
                WriteLn(ParamStr(0), ' filename');
                Halt(1);
        END;
        Assign(ctx.f, ParamStr(1));
        {$I-}
        Reset(ctx.f, 1);
        i := ioResult;
        {$I+}
        IF i <> 0 THEN BEGIN
                WriteLn('Error ', i, ' while open ', ParamStr(1));
        END ELSE BEGIN
                ctx.inited := false;
                GraphMode;
                r := qoi_decode(@ctx, qread, qwrite, @desc, 3);
                Close(ctx.f);
                IF r THEN  ReadLn;
                TextMode;
                IF r THEN BEGIN
                        Writeln('---------------------------------');
                        Writeln('QOI Info:');
                        Writeln;
                        Writeln('Magic:      ', desc.magic);
                        Writeln('Width:      ', desc.width);
                        Writeln('Height:     ', desc.height);
                        Writeln('Channels:   ', desc.channels);
                        Writeln('Colorspace: ', desc.colorspace);
                        Writeln('---------------------------------');
                        Writeln;
                END ELSE BEGIN
                        WriteLn('Error while decode file.');
                END;
        END;
END.
