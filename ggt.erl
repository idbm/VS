-module(ggt).
-export([start/7]).
-record(worker , {clientname, rechterNach, linkerNachbar, datei, arbeitsZeit, koordinatorname, nameservicenode, mi}).

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
	
  
ggt(X,X,State)-> abs(X);
ggt(X,0,State)->  abs(X);
ggt(0,X,State)->  abs(X);
ggt(Mi,Y,State) when Y < Mi ->  
  
  MiNeu=ggt(Y,((Mi-1) rem Y)+ 1,State), MiNeu;

ggt(Mi,Y,State) when Y > Mi -> MiNeu=ggt(Mi,((Y-1) rem Mi)+ 1,State), MiNeu.
            
    
  
  
  
loop(State)->
  Datei= State#worker.datei,
  Koordinatorname= State#worker.koordinatorname,
  Clientname= State#worker.clientname,
  Nameservice = global:whereis_name(nameservice),
         
  receive
    {setneighbors,LeftN,RightN} ->
      Opts = State#worker{linkerNachbar=LeftN, rechterNach=RightN},
      werkzeug:logging(Datei,lists:concat(["Linker Nachbar: ", LeftN, " (", Opts#worker.linkerNachbar,") gebunden \n"])),
      werkzeug:logging(Datei,lists:concat(["Rechter Nachbar: ", RightN, " (", Opts#worker.rechterNach,") gebunden \n"])),
      loop(Opts);
    
      {setpm,Mi} -> 
        werkzeug:logging(Datei,lists:concat([" initiales Mi ", Mi, "\n"])), 
        Opts = State#worker{mi=Mi},
        loop(Opts);
      
      {sendy,Y} -> 
        werkzeug:logging(Datei,lists:concat([" Y ", Y, "\n"])),
        Mi = State#worker.mi,  
        LN = State#worker.linkerNachbar,
        RN = State#worker.rechterNach,  
        MiNeu = ggt(Mi,Y,State),
        case {Mi =/= MiNeu} of
          {true}-> spawn(fun() -> rekursion(MiNeu,Mi,State)end), Opts = State#worker{mi=MiNeu}, loop(Opts);
          {false}-> loop(State)
        end
        
       
    end.
    
    rekursion(MiNeu, Mi,State)->
      LN = State#worker.linkerNachbar,
      RN = State#worker.rechterNach, 
      Datei= State#worker.datei,
      Koordinatorname= State#worker.koordinatorname,
      Clientname= State#worker.clientname,
      Nameservice = global:whereis_name(nameservice),
      
        Koordinatorname ! {briefmi,{Clientname,MiNeu,werkzeug:timeMilliSecond()}},
        Nameservice ! {self(),{lookup,LN}},
        receive
          {NameA,NodeA} ->  werkzeug:logging(Datei,lists:concat([NameA, " NameA ",NodeA, " NodeA\n"])), {NameA,NodeA} ! {sendy,MiNeu};
          not_found -> werkzeug:logging(Datei,lists:concat([LN, " not founded"]))
        end,

        Nameservice ! {self(),{lookup,RN}},
        receive
          {NameB,NodeB} -> werkzeug:logging(Datei,lists:concat([NameB, " NameB ",NodeB, " NodeB\n"])), {NameB,NodeB} ! {sendy,MiNeu};
          not_found -> werkzeug:logging(Datei,lists:concat([RN, " not founded"]))
        end.
        
      
   
    

  
  