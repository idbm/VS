-module(koordinator).
-export([start/0]).
-record(state, {anzahl_ggt_prozesse, verzoegerungszeit,
                  timeout, ggt, zustand=initial,
                 ggt_prozesse=[], datei, nameservicenode, koordinatorname}).

start() ->
	{ok, HostName} = inet:gethostname(),
	Datei = lists:concat(["koordinator@",HostName,".log"]),	
			
	{ok, ConfigListe} = file:consult("koordinator.cfg"),
  {ok, Nameservicenode} = werkzeug:get_config_value(nameservicenode, ConfigListe),
  {ok, Koordinatorname} = werkzeug:get_config_value(koordinatorname, ConfigListe),
  {ok, Ggtprozessnummer} = werkzeug:get_config_value(ggtprozessnummer, ConfigListe),
  {ok, Termzeit} = werkzeug:get_config_value(termzeit, ConfigListe),
  {ok, Arbeitszeit} = werkzeug:get_config_value(arbeitszeit, ConfigListe),
	werkzeug:logging(Datei,"koordinator.cfg gelesen \n"),
	
  KoordinatorPid = spawn(fun() -> init(#state{anzahl_ggt_prozesse=Ggtprozessnummer, verzoegerungszeit=Arbeitszeit, timeout=Termzeit, datei=Datei, nameservicenode=Nameservicenode, koordinatorname=Koordinatorname}) end),
	Zeit = lists:concat(["Koordinator@",HostName," Startzeit: ",werkzeug:timeMilliSecond()]),
	Inhalt = lists:concat([Zeit," mit PID ", pid_to_list(KoordinatorPid), "\n"]),
	werkzeug:logging(Datei,Inhalt),
	
	%% Beim Nameserver anmelden
	net_adm:ping(Nameservicenode),
	Nameservice = global:whereis_name(nameservice),
	Nameservice ! {self(),{rebind, Koordinatorname ,node()}},
    receive ok -> werkzeug:logging(Datei,"..bind.done.\n");
            in_use -> werkzeug:logging(Datei,"..schon gebunden.\n")
    end,
  
  %% Lokal registrieren    
  case {is_pid(whereis(Koordinatorname))} of
	  {true} -> unregister(Koordinatorname);
	  {false} -> ok
	end,
  erlang:register(Koordinatorname,KoordinatorPid),
	KoordinatorPid.       
      	
 init(State) ->
  Datei= State#state.datei,
  case {State#state.zustand} of  
    {initial} ->                                                                                    %% Zustand initial ist der Default Wert.
      receive
        {getsteeringval, From} ->                                                                   %%Der Starter fragt nach den Config-Werten
          werkzeug:logging(Datei,lists:concat(["getsteeringval: ", pid_to_list(From), "\n"])),
          ArbeitsZeit = State#state.verzoegerungszeit,
          TermsZeit = State#state.timeout,
          GGTProzessnummer = State#state.anzahl_ggt_prozesse,
          From ! {steeringval,ArbeitsZeit,TermsZeit,GGTProzessnummer},                              %%Werte werden geschickt
          init(State);                                                                              %%Warte wieder auf Nachrichten
          
        {hello,Clientname} ->                                                                       %%Arbeiterprozess meldet sich
          Mylist = State#state.ggt_prozesse,
          NewList = lists:append([Clientname], Mylist),                                             %%ggtP-Name kommt in die Liste der angemeldeten Prozesse
          werkzeug:logging(Datei,lists:concat(["hello: ", Clientname, "\n"])),
          init(State#state{ggt_prozesse=NewList});                                                  %%Warte wieder auf Nachrichten. ProzessListe aktuallisiert
          
        {bereit} ->                                                                                 %% Mit {bereit} wird der Zustand geändert 
          Opts =State#state{zustand=bereit},                                                        
          
          werkzeug:logging(Datei,"Anmeldefrist fuer ggT-Prozesse abgelaufen.\n"),                   
          List = State#state.ggt_prozesse,                                                          %%Liste mit den Namen aller angemeldeten Prozesse  
          AnzahlDerProzesse = length(List),
          werkzeug:logging(Datei,lists:concat(["Anzahl der Prozesse: ", AnzahlDerProzesse, "\n"])), %%Anzahl der Prozesse wird ausgegeben
          
          Nameservice = global:whereis_name(nameservice),                                           %%foreach für das Ausgeben der Prozesse mit Name und Node  
          lists:foreach(fun(Elem)->
            Nameservice ! {self(),{lookup,Elem}},
            receive
              {Name,Node} -> Nachricht = lists:concat(["ggT-Prozess ", Elem, " (", Name, ") ", "auf ", Node, " gebunden.\n" ]),
                             werkzeug:logging(Datei,Nachricht);
              not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
            end
          
          end,List),
          
          NewList = shuffle(List),                                                                    %% Die Liste wird vermischt bevor der Ring aufgebaut wird
          [Head, Next| T] = NewList,                                                                  %% Head=Erste, Next=Zweite, T=Rest der Liste  
          Last = lists:last(T),                                                                       %%Letzte in der Liste
          Nameservice ! {self(),{lookup,Head}},                                                       %%Hier werden die Nachbarn des ersten Prozesses gesetzt so dass T <- Head -> Next
            receive
              {Name,Node} -> {Name,Node}! {setneighbors,Last,Next}, 
                              connect(Head, NewList,Datei);                                           %% Hier wird der Ring weiter aufgebaut siehe connect().
              not_found -> werkzeug:logging(Datei,lists:concat([Head, " not founded"]))
            end,
          init(Opts)                                                                                  %%Hier wird in den Zustand "bereit" gewechselt
        end;
        
        
        {bereit} ->                                                                                   %%Startbereit für eine Berechnung
          werkzeug:logging(Datei,"Ich bin jetzt bereit \n"),
          werkzeug:logging(Datei,"Warte auf Nachrich: {berechnen} um die Berechnung zu starten\n"),
          receive
            {berechnen}->                                                                             %%Mit {berechnen} wird manuell eine Berrechnung gestartet      
                List = State#state.ggt_prozesse,
                Nameservice = global:whereis_name(nameservice),
                
                Ggt_gewuenscht =random:uniform(100),                                                  %%Ziel ggt: zum überprüfen der Ergebnisse
                werkzeug:logging(Datei,lists:concat(["Ziel:" , Ggt_gewuenscht, "\n"])),
                
                lists:foreach(fun(Elem)->                                                             %%for each fuer das Senden des initialen Mi-Wertes an jedem Prozess
                  Nameservice ! {self(),{lookup,Elem}},
                  receive
                    {NameA,NodeA} -> Mi = Ggt_gewuenscht * lists:foldl(fun(X,Acc)-> trunc(math:pow(X,(-1 + random:uniform(3)))) * Acc end, 1, [3,5,11,13,23,37]), 
                                  {NameA,NodeA}! {setpm,Mi}, werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", NameA, " (", NodeA,") initiales Mi ", Mi, " gesendet\n"])) ;
                    not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
                  end
                
                end,List),
                  
                Number_selected = round((length(List)*15)/100),                                       %% 15% der Prozesse werden ausgewählt  
                werkzeug:logging(Datei,lists:concat(["NumberOfProz: ", Number_selected, " \n"])),
                ProsList =shuffle(List),                                                              %% Liste wird gemischt(für den Zufallfaktor)  
                case {(Number_selected < 2)} of                                                       %% Initiales Y wird geschickt. Mindesten 2 Prozesse Ausgewählt      
                 {true} -> spawn(fun() -> sendY(ProsList,2,Ggt_gewuenscht, Datei)end), 
                          berechne(Datei);  
                  
                 {false}-> spawn(fun() -> sendY(ProsList,Number_selected,Ggt_gewuenscht,Datei)end), 
                          berechne(Datei)
                  
                end
                
            end
        end.
        
            
    berechne(Datei)->                                                                               %% Hier wird auf die Werte der berechnung gewartet
    receive
            {briefmi,{Clientname,CMi,CZeit}} -> werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", Clientname, " meldet neues Mi ", CMi, " um", CZeit,"\n"])) , berechne(Datei)
          end.   
        
    
    sendY(ProsList, NumberSelected,Ggt_gewuenscht,Datei)->
      Nameservice = global:whereis_name(nameservice), 
      NewList = lists:sublist(ProsList, NumberSelected),
      lists:foreach(fun(Elem)->
      Nameservice ! {self(),{lookup,Elem}},
      receive
            {Name,Node} ->  Y = Ggt_gewuenscht * lists:foldl(fun(X,Acc)-> trunc(math:pow(X,(-1 + random:uniform(3)))) * Acc end, 1, [3,5,11,13,23,37]), 
                            {Name,Node}! {sendy,Y}, werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", Name, " (", Node,") initiales Y ", Y, " gesendet\n"])) ;
            not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
          end
        
        end,NewList).
      
        
    
          
    shuffle(List) ->
%% Determine the log n portion then randomize the list.
   randomize(round(math:log(length(List)) + 0.5), List).

  randomize(1, List) ->
     randomize(List);
  randomize(T, List) ->
     lists:foldl(fun(_E, Acc) ->
                    randomize(Acc)
                 end, randomize(List), lists:seq(1, (T - 1))).
  
  randomize(List) ->
     D = lists:map(fun(A) ->
                      {random:uniform(), A}
               end, List),
     {_, D1} = lists:unzip(lists:keysort(1, D)), 
     D1.
     
      
     
     %% If only two elements are left in the list just point
      %% the first process to the next process. And point the
      %% the last process to the first process.
  connect(Head, [H,N], Datei) ->
       Nameservice = global:whereis_name(nameservice),
       Nameservice ! {self(),{lookup, N}},
       receive
              {Name,Node} -> 
                {Name,Node}! {setneighbors,H,Head}, 
                werkzeug:logging(Datei,lists:concat(["ggT-Prozess ", N, "(", Node, ") ueber linken (",H ,") und rechten (", Head,") informiert. \n" ]));
              not_found -> werkzeug:logging(Datei,lists:concat([N, " not founded"]))
            end;
       
       
  connect(Head, [H,N,N1|T], Datei) ->
       Nameservice = global:whereis_name(nameservice),
       Nameservice ! {self(),{lookup, N}},
       receive
              {Name,Node} -> 
                {Name,Node}! {setneighbors,H,N1}, 
                werkzeug:logging(Datei,lists:concat(["ggT-Prozess ", N, "(", Node, ") ueber linken (",H ,") und rechten (", N1,") informiert. \n" ])),
                connect(Head, [N,N1|T], Datei);
              not_found -> werkzeug:logging(Datei,lists:concat([N, " not founded"]))
            end. 