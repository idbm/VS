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
	
	
	KoordinatorPid = spawn(fun() -> init(#state{anzahl_ggt_prozesse=Ggtprozessnummer, verzoegerungszeit=Arbeitszeit, timeout=Termzeit, datei=Datei, nameservicenode=Nameservicenode, koordinatorname=Koordinatorname}) end),
	%%register(Koordinatorname, KoordinatorPid),
	Zeit = lists:concat(["Koordinator@",HostName," Startzeit: ",werkzeug:timeMilliSecond()]),
	Inhalt = lists:concat([Zeit," mit PID ", pid_to_list(KoordinatorPid), "\n"]),
	werkzeug:logging(Datei,Inhalt),
	werkzeug:logging(Datei,"koordinator.cfg gelesen \n"),
	
	case {is_pid(whereis(Koordinatorname))} of
	  {true} -> unregister(Koordinatorname);
	  {false} -> ok
	end,
	erlang:register(Koordinatorname,KoordinatorPid),
	
	net_adm:ping(Nameservicenode),
	Nameservice = global:whereis_name(nameservice),
	Nameservice ! {self(),{rebind, Koordinatorname ,node()}},
    receive ok -> werkzeug:logging(Datei,"..bind.done.\n");
            in_use -> werkzeug:logging(Datei,"..schon gebunden.\n")
          end,
  KoordinatorPid.
	%%global:register_name(Koordinatorname, KoordinatorPid),
		
	
  %%register(Koordinatorname,KoordinatorPid),
 	%%werkzeug:logging(Datei,"lokal registriert").
 	
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
       
      	
 init(State) ->
  Datei= State#state.datei,
  case {State#state.zustand} of  
    {initial} ->
      receive
        {getsteeringval, From} ->
          werkzeug:logging(Datei,lists:concat(["getsteeringval: ", pid_to_list(From), "\n"])),
          ArbeitsZeit = State#state.verzoegerungszeit,
          TermsZeit = State#state.timeout,
          GGTProzessnummer = State#state.anzahl_ggt_prozesse,
          From ! {steeringval,ArbeitsZeit,TermsZeit,GGTProzessnummer},
          init(State);
          
        {hello,Clientname} ->
          Mylist = State#state.ggt_prozesse,
          NewList = lists:append([Clientname], Mylist),
          io:format("NewList~p~n",[NewList]),
          werkzeug:logging(Datei,lists:concat(["hello: ", Clientname, "\n"])),
          init(State#state{ggt_prozesse=NewList});
          
        {bereit} ->
          Opts =State#state{zustand=bereit},
          werkzeug:logging(Datei,"Anmeldefrist fuer ggT-Prozesse abgelaufen.\n"), 
          List = State#state.ggt_prozesse,
          io:format("List~p~n",[List]),
          AnzahlDerProzesse = length(List),
          werkzeug:logging(Datei,lists:concat(["Anzahl der Prozesse: ", AnzahlDerProzesse, "\n"])), 
          Nameservice = global:whereis_name(nameservice),
          lists:foreach(fun(Elem)->
            Nameservice ! {self(),{lookup,Elem}},
            receive
              {Name,Node} -> Nachricht = lists:concat(["ggT-Prozess ", Elem, " (", Name, ") ", "auf ", Node, " gebunden.\n" ]),
                             werkzeug:logging(Datei,Nachricht);
              not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
            end
          
          end,List),
          io:format("List~p~n",[List]),
          NewList = shuffle(List),
          io:format("NewList~p~n",[NewList]),
          [Head, Next| T] = NewList,
          Last = lists:last(T),
          Nameservice ! {self(),{lookup,Head}},
            receive
              {Name,Node} -> {Name,Node}! {setneighbors,Last,Next}, io:format("Name~p~n",[Name]), connect(Head, NewList,Datei);
              not_found -> werkzeug:logging(Datei,lists:concat([Head, " not founded"]))
            end,
          init(Opts)
        end;
        
        
        {bereit} -> 
          werkzeug:logging(Datei,"Ich bin jetzt bereit \n"),
          List = State#state.ggt_prozesse,
          Nameservice = global:whereis_name(nameservice),
          Ggt_gewuenscht =random:uniform(100),
          werkzeug:logging(Datei,lists:concat(["Ziel:" , Ggt_gewuenscht, "\n"])),
          lists:foreach(fun(Elem)->
            Nameservice ! {self(),{lookup,Elem}},
            receive
              {NameA,NodeA} -> Mi = Ggt_gewuenscht * lists:foldl(fun(X,Acc)-> trunc(math:pow(X,(-1 + random:uniform(3)))) * Acc end, 1, [3,5,11,13,23,37]), 
                            {NameA,NodeA}! {setpm,Mi}, werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", NameA, " (", NodeA,") initiales Mi ", Mi, " gesendet\n"])) ;
              not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
            end
          
          end,List),
          
          Nameservice ! {self(),{lookup,hd(List)}},
           receive
              {Name,Node} -> Y = Ggt_gewuenscht * lists:foldl(fun(X,Acc)-> trunc(math:pow(X,(-1 + random:uniform(3)))) * Acc end, 1, [3,5,11,13,23,37]), 
                            {Name,Node}! {sendy,Y}, werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", Name, " (", Node,") initiales Y ", Y, " gesendet\n"])) ;
              not_found -> werkzeug:logging(Datei,lists:concat([hd(List), " not founded"]))
            end,
            berechne(Datei) 
          
         %% Number_selected = round((length(List)*15)/100),
         %% werkzeug:logging(Datei,lists:concat(["NumberOfProt: ", Number_selected, " \n"])),
         %% ProsList =shuffle(List),
        %%  case {(Number_selected < 2)} of
         %%   {true} -> NewList = lists:sublist(ProsList, Number_selected+3),
          %%            lists:foreach(fun(Elem)->
          %%              Nameservice ! {self(),{lookup,Elem}},
              %%          receive
                %%          {Name,Node} ->  Y = Ggt_gewuenscht * lists:foldl(fun(X,Acc)-> trunc(math:pow(X,(-1 + random:uniform(3)))) * Acc end, 1, [3,5,11,13,23,37]), 
                 %%                         {Name,Node}! {sendy,Y}, werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", Name, " (", Node,") initiales Y ", Y, " gesendet\n"])) ;
                  %%        not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
                   %%     end
                      
                    %%  end,NewList), berechne(Datei) ;
            
           %% {false}-> NewList = lists:sublist(ProsList, Number_selected+1),
               %%       lists:foreach(fun(Elem)->
              %%        Nameservice ! {self(),{lookup,Elem}},
                %%      receive
                %%        {Name,Node} -> Y = Ggt_gewuenscht * lists:foldl(fun(X,Acc)-> trunc(math:pow(X,(-1 + random:uniform(3)))) * Acc end, 1, [3,5,11,13,23,37]), 
                          %%            {Name,Node}! {sendy,Y}, werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", Name, " (", Node,") Initiales Y ", Y, " gesendet\n"]));
                       %% not_found -> werkzeug:logging(Datei,lists:concat([Elem, " not founded"]))
                     %% end
                    
                   %%  end,NewList), berechne(Datei) 
            
         %% end
          
                  
        end.
        
        
    berechne(Datei)-> 
    receive
            {briefmi,{Clientname,CMi,CZeit}} -> werkzeug:logging(Datei,lists:concat(["ggt-Prozess ", Clientname, " meldet neues Mi ", CMi, " um", CZeit,"\n"])) , berechne(Datei)
          end.    