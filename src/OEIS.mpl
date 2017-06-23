OEIS := module()
    option package;
    export Get, ModuleLoad, Parse, Print, Search, _pexports;
    local URLpath, ConvertUTF8, pCM;

    #Hide Parse from main package exports
    _pexports := proc()
        remove( member, [exports(thismodule)], [':-Parse', ':-ModuleLoad', ':-_pexports'] );
    end proc:

    ModuleLoad := proc()
        pCM := ContextMenu:-CurrentContext:-Copy():
        pCM:-Queries:-Add( 
            "Is mypackage Loaded",
            proc()
                member( ':-OEIS', packages() );
            end proc);
        pCM:-Queries:-Add(
            "has >= 6 entries",
            proc()
                if numelems([ args ]) >= 6 then
                    true;
                else
                    false;
                end if; 
            end proc);
        pCM:-Entries:-AddMultiple( 
        [   "Search OEIS", 
            "OEIS:-Search(%EXPR)", 
            'exprseq',      
            'helpstring' = "Search the OEIS for this expression sequence",
            'test' = "has >= 6 entries" ],
        [   "Retrieve from OEIS", 
            "OEIS:-Get(%EXPR)", 
            'integer',
            'helpstring' = "Retrieve information from OEIS for integer sequence ID"],
            'active'="Is mypackage Loaded",
            'category'="Category 3" );
        ContextMenu:-Install(pCM);
    end proc:

    URLpath := "http://oeis.org/";

    Search := proc()
        option cache;
        local argsin, i, numresults, oeis_json, parsed_value, searchstring;
        parsed_value := Array(1..0):

        if type( [ args ], 'list'('integer') ) = true and nargs < 6 or ( type( [ args ], 'list'('integer') ) = false and not type( args, 'string') ) then
            error "6 or more integers required";
        elif type( [ args ], 'list'('integer') ) = true then
            argsin := :-map( :-convert, [ args ], ':-string' );
            searchstring := cat( argsin[1], seq( op( [",", argsin[i]] ), i = 2..numelems( argsin ) ) );
        elif type( args, 'string') then
            argsin := [args];
            searchstring := StringTools:-SubstituteAll(op(argsin), " ", "%20");
        else
            error "in arguments, expected integer sequence or string; received", op( [ args ] );        
        end if;

        oeis_json := URL:-Get( cat( URLpath, "search?fmt=json&q=", searchstring ) );
        parsed_value(1) := eval( JSON:-ParseString( oeis_json ) );
        numresults := parsed_value[1]["count"];
        printf( cat("%d result", `if`(numresults<>1, "s", "")," found"), numresults );
        #userinfo( 2, 'Search', `\n`, numresults, sprintf( cat( "result", `if`(numresults<>1, "s", ""), " found" ) ) );

        if numresults = 0 then
            return NULL;
        elif numresults > 0 and numresults <= 10 then
            return seq( parsed_value[1]["results"][i]["number"], i = 1..numresults );
        elif numresults <= 100 then
            for i from 1 to iquo(numresults-1,10) do
                parsed_value(i+1) := eval( JSON:-ParseString( URL:-Get( cat( URLpath, "search?fmt=json&start=", i*10, "&q=", searchstring ) ) ) );
            end do:
            return seq( op( [ seq( parsed_value[j]["results"][i]["number"], i = 1..numelems( parsed_value[j]["results"]) ) ] ), j = 1..iquo(numresults-1, 10)+1 );
        else
            error "found %1 results; this exceeds the maximum number of results (100) - try a more precise query", numresults;
        end if;
    end proc:

    Get := proc( ID, {format::identical(json,text):='json'} )
        option cache;
        local oeis_return, parsed_value;
        if format = 'json' then
            oeis_return := URL:-Get( cat( URLpath, "search?fmt=json&q=id:A", ID ) );
            parsed_value := JSON:-ParseString( oeis_return, _rest );
            if parsed_value["count"] <> 0 then
                return eval( parsed_value )["results"][1]; 
            else
                return printf( "%s", "No results found" );
            end if;
       elif format = 'text' then
            URL:-Get( cat( URLpath, "search?fmt=text&q=id:A", ID ) );
       end if;
    end proc:

    Print := proc( ID, {output::list:='all'} )
        local oeis_ds, df_label, i, df, vals;
        df_label := Array(1..0):
        oeis_ds := Array(1..0):
        if hastype( ID, list ) then
            vals := ID;
        else
            vals := [ID];
        end if;

        for i from 1 to numelems(vals) do
            if hastype( vals[i], {'DataSeries', 'table' }) then
                oeis_ds(i) := :-convert( vals[i], DataSeries):
            elif hastype( vals[i], {'record' }) then
                error "unable to print record form";
            else
                oeis_ds(i) := OEIS:-Get(vals[i], ':-output'='DataSeries'):
            end if;
            try
                if member( oeis_ds[i]["number"], df_label) then
                    df_label(i) := cat(oeis_ds[i]["number"],"_",i);
                else
                    df_label(i) := oeis_ds[i]["number"];
                end if;
            catch:
                df_label(i) := "OEIS";
            end try;

            if i = 1 then
                df := DataFrame( Parse~(oeis_ds[i]), 'columns'=[df_label[i]] );
            else
                df:= Append( df, DataFrame( Parse~(oeis_ds[i]), 'columns'=[df_label[i]] ), 'mode' = 'column' );
            end if;
        end do:

        if member("UTF8", PackageTools:-ListInstalledPackages() ) = false then
            WARNING("the UTF8 package is required for parsing, install using PackageTools:-Install( 6304612005969920 ); skipped parsing input.");
        end if;

        if output = 'all' then
            Tabulate(df);
        else
            
            Tabulate(df[[seq(`if`(member(i, RowLabels(df)), i, NULL), i in output)],..])
        end if;
        return NULL;
    end proc:

    Parse := proc( OEISobj )
        if member("UTF8", PackageTools:-ListInstalledPackages() ) = false then
            return args;
        else
            try
                cat(op(ConvertUTF8~(OEISobj)));
            catch: 
                ConvertUTF8~(OEISobj);
            end try;
        end if;
    end proc:

    ConvertUTF8 := proc( str )
	    local i, tempstring, uniindex;
        try
            tempstring := str;
            uniindex := [StringTools:-SearchAll("\u",str)];
            if uniindex <> [] then
                for i in uniindex  do
                    tempstring := StringTools:-Substitute(tempstring, str[i..i+5], UTF8:-unicode(str[i+2..i+5]));  
                end do:
            end if;
            return tempstring;
        catch:
            return str;
        end try;
    end proc:

end module:
