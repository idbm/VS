-module(ggt).
-export([start/7]).
-record(worker , {clientname, rechterNach, linkerNachbar, datei, arbeitsZeit, koordinatorname, nameservicenode, mi, timerRef=timer:start(), termZeit}).

start(StarterName,Elem,Nummer,ArbeitsZeit,TermZeit, Koordinatorname, Nameservicenode) ->
    
  {ok, HostName} = inet:gethostname(),
	
  Ggt_Name =erlang:list_to_atom(lists:concat([StarterName,Elem,Nummer])),
  Datei = lists:concat([Ggt_Name,"@",HostName,".log"]),
  
  Zeit = lists:concat([Ggt_Name,"@",HostName," Startzeit: ",werkzeug:timeMilliSecond()]),
	Inhalt = lists:concat([Zeit," mit PID ", pid_to_list(self()), "\n"]),
	werkzeug:logging(Datei,Inhalt),
	
	case {is_pid(whereis(Ggt_Name))} of
	  {true} -> unregister(Ggt_Name);
	  {false} -> ok
	end,
	erlang:register(Ggt_Name,self()),
  werkzeug:logging(Datei,lists:concat(["lokal registriert mit name: ", (Ggt_Name), " und Pid: " , pid_to_list(self()), "\n" ])),
  
  net_adm:ping(Nameservicenode),
	Nameservice = global:whereis_name(nameservice),
	Nameservice ! {self(),{rebind, Ggt_Name ,node()}},
  receive ok -> werkzeug:logging(Datei,"..bind.done.\n");
          in_use -> werkzeug:logging(Datei,"..schon gebunden.\n")
        end,
  werkzeug:logging(Datei,"Nameservice bind \n"),
  Koordinatorname ! {hello,Ggt_Name},  
  werkzeug:logging(Datei,"Beim Koordinator angemeldet\n"),
  loop(#worker{clientname=Ggt_Name, datei=Datei, arbeitsZeit=ArbeitsZeit, koordinatorname=Koordinatorname, nameservicenode=Nameservicenode, termZeit=TermZeit}).
	
	  
ggt(X,X,State)-> abs(X);
ggt(X,0,State)->  abs(X);
ggt(Mi,Y,State) when Y < Mi ->  
  MiNeu=ggt(Y,((Mi-1) rem Y)+ 1,State),
  spawn(fun() -> sendToNeigh(MiNeu,State)end), 
  MiNeu;

ggt(Mi,Y,State) when Y > Mi ->  MiNeu=ggt(Mi,((Y-1) rem Mi)+ 1, State), MiNeu.
            
    
  
  
  
loop(State)->
  Datei= State#worker.datei, 
         
  receive
    {setneighbors,LeftN,RightN} ->
      Opts = State#worker{linkerNachbar=LeftN, rechterNach=RightN},
      werkzeug:logging(Datei,lists:concat(["Linker Nachbar: ", LeftN, " (", Opts#worker.linkerNachbar,") gebunden \n"])),
      werkzeug:logging(Datei,lists:concat(["Rechter Nachbar: ", RightN, " (", Opts#worker.rechterNach,") gebunden \n"])),
      loop(Opts);
    
      {setpm,Mi} -> 
        werkzeug:logging(Datei,lists:concat([" initiales Mi ", Mi, "\n"])), 
        Opts=State#worker{mi=Mi},
        loop(Opts);
         
          
      {sendy,Y} -> 
        TermZ=State#worker.termZeit,
        Mi = State#worker.mi, 
        Tref=erlang:send_after(TermZ,self(),{startAbstimmung}),
        MiNeu= ggt(Mi,Y,State),
        Opts =State#worker{mi=MiNeu,timerRef=Tref},
        loop(Opts);
        
          
                       
      {abstimmung,From}->
        Koordinatorname= State#worker.koordinatorname,
        case {From =:= self()} of
          {true} -> Koordinatorname ! {briefterm,{State#worker.clientname,State#worker.mi,werkzeug:timeMilliSecond()}}, loop(State);
          {false}-> case {(erlang:read_timer(State#worker.timerRef) < State#worker.arbeitsZeit/2)} of
                      {true} -> Nameservice = global:whereis_name(nameservice),
                                Nameservice ! {self(),{lookup,State#worker.rechterNach}},
                                receive
                                  {NameA,NodeA} ->  {NameA,NodeA} ! {abstimmung,From}, loop(State);
                                  not_found -> werkzeug:logging(Datei,lists:concat([State#worker.rechterNach, " not founded"])), loop(State)
                                end;
                      {false}-> loop(State)
                    end
                  end;
                  
      {startAbstimmung}->
        Nameservice = global:whereis_name(nameservice),
        werkzeug:logging(Datei,"Ich bin hier"),
        Nameservice ! {self(),{lookup,State#worker.rechterNach}},
                                receive
                                  {NameB,NodeB} ->  {NameB,NodeB} ! {abstimmung,self()}, loop(State);
                                  not_found -> werkzeug:logging(Datei,lists:concat([State#worker.rechterNach, " not founded"]))
                                end,
                                loop(State)
        
        
        
        
        
       
    end.
    
    
      
    sendToNeigh(MiNeu,State)->
      LN = State#worker.linkerNachbar,
      RN = State#worker.rechterNach, 
      Datei= State#worker.datei,
      Koordinatorname= State#worker.koordinatorname,
      Clientname= State#worker.clientname,
      Nameservice = global:whereis_name(nameservice),
      
        Koordinatorname ! {briefmi,{Clientname,MiNeu,werkzeug:timeMilliSecond()}},
        Nameservice ! {self(),{lookup,LN}},
        receive
          {NameA,NodeA} ->  {NameA,NodeA} ! {sendy,MiNeu};
          not_found -> werkzeug:logging(Datei,lists:concat([LN, " not founded"]))
        end,

        Nameservice ! {self(),{lookup,RN}},
        receive
          {NameB,NodeB} -> {NameB,NodeB} ! {sendy,MiNeu};
          not_found -> werkzeug:logging(Datei,lists:concat([RN, " not founded"]))
        end.
        
      
   
    

  
  