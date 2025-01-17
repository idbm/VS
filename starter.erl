-module(starter).
-export([start/1]).
-record(state1, {startername, koordinatorname, datei, nameservicenode}).



start(Nummer) ->
  
  {ok, HostName} = inet:gethostname(),
	Datei = lists:concat(["ggtStarter@",HostName,".log"]),	
		
	{ok, ConfigListe} = file:consult("ggt.cfg"),
  {ok, Praktikumsgruppe} = werkzeug:get_config_value(praktikumsgruppe, ConfigListe),
  {ok, Teamnummer} = werkzeug:get_config_value(teamnummer, ConfigListe),
  {ok, Nameservicenode} = werkzeug:get_config_value(nameservicenode, ConfigListe),
  {ok, Koordinatorname} = werkzeug:get_config_value(koordinatorname, ConfigListe),
  werkzeug:logging(Datei,"ggt.cfg gelesen \n"),
  
  StarterName = lists:concat([Praktikumsgruppe,Teamnummer,Nummer]),
  StarterPid = spawn(fun() -> loop(#state1{startername=StarterName, koordinatorname=Koordinatorname, datei=Datei, nameservicenode=Nameservicenode}, Nummer) end),
	
  Zeit = lists:concat(["Starter@",HostName," Startzeit: ",werkzeug:timeMilliSecond()]),
	Inhalt = lists:concat([Zeit," mit PID ", pid_to_list(StarterPid), "\n"]),
	werkzeug:logging(Datei,Inhalt).
	
	loop(State, Nummer) ->
    Datei= State#state1.datei,
    StarterName = State#state1.startername,
    Nameservicenode = State#state1.nameservicenode,
    Koordinatorname = State#state1.koordinatorname,
        	 
	  net_adm:ping(Nameservicenode),
    Nameservice = global:whereis_name(nameservice),
    Nameservice ! {self(),{lookup,Koordinatorname}},
            receive
              {Name,Node} -> {Name,Node} ! {getsteeringval, self()},
                              werkzeug:logging(Datei, lists:concat([getsteeringval, "\n"])),
                              receive
                                {steeringval,ArbeitsZeit,TermZeit,GGTProzessnummer} ->
                                    werkzeug:logging(Datei,lists:concat(["ArbeitsZeit: ",ArbeitsZeit, "; TermZeit: ", TermZeit, "; GGTProzessnummer", GGTProzessnummer, "\n" ])),
                                    List = lists:seq(1, GGTProzessnummer),
                                    lists:foreach(fun(Elem)->
                                        spawn(fun() ->
                                              ggt:start(StarterName,Elem,Nummer,ArbeitsZeit,TermZeit, {Name,Node}, Nameservicenode)
                                            end)
                                    end,List)
                                  end;
               not_found -> werkzeug:logging(Datei,lists:concat([Koordinatorname, " not founded"]))
            end.
   