-module(ggt).
-export([start/7]).
-record(worker , {clientname, rechterNach, linkerNachbar, datei, arbeitsZeit, koordinatorname, nameservicenode}).

start(StarterName,Elem,Nummer,ArbeitsZeit,TermZeit, Koordinatorname, Nameservicenode) ->
    
  {ok, HostName} = inet:gethostname(),
	
  Ggt_Name =erlang:list_to_atom(lists:concat([StarterName,Elem,Nummer])),
  Datei = lists:concat([Ggt_Name,"@",HostName,".log"]),
  
  GgtPid = spawn(fun() -> loop(#worker{clientname=Ggt_Name, datei=Datei, arbeitsZeit=ArbeitsZeit, koordinatorname=Koordinatorname, nameservicenode=Nameservicenode}) end),
	Zeit = lists:concat([Ggt_Name,"@",HostName," Startzeit: ",werkzeug:timeMilliSecond()]),
	Inhalt = lists:concat([Zeit," mit PID ", pid_to_list(GgtPid), "\n"]),
	werkzeug:logging(Datei,Inhalt),
	case {is_pid(whereis(Ggt_Name))} of
	  {true} -> unregister(Ggt_Name);
	  {false} -> ok
	end,
	erlang:register(Ggt_Name,GgtPid),
  werkzeug:logging(Datei,lists:concat(["lokal registriert mit name: ", (Ggt_Name), " und Pid: " , pid_to_list(GgtPid), "\n" ])),
	
	net_adm:ping(Nameservicenode),
	Nameservice = global:whereis_name(nameservice),
	Nameservice ! {self(),{rebind, Ggt_Name ,node()}},
  receive ok -> werkzeug:logging(Datei,"..bind.done.\n");
          in_use -> werkzeug:logging(Datei,"..schon gebunden.\n")
        end,
  werkzeug:logging(Datei,"Nameservice bind \n"),
   
  Koordinatorname ! {hello,Ggt_Name},  
  werkzeug:logging(Datei,"Beim Koordinator angemeldet\n").
	
  
loop(State)->
  Datei= State#worker.datei,
        
  receive
    {setneighbors,LeftN,RightN} ->
      Opts = State#worker{linkerNachbar=LeftN, rechterNach=RightN},
      werkzeug:logging(Datei,lists:concat(["Linker Nachbar: ", LeftN, " (", Opts#worker.linkerNachbar,") gebunden \n"])),
      werkzeug:logging(Datei,lists:concat(["Rechter Nachbar: ", RightN, " (", Opts#worker.rechterNach,") gebunden \n"]))
           
    end,
    loop(Opts).

  
  