-----------------------------------------------------------------------------------------------------------------------
-- Company:         Politecnico di Milano
-- Engineers:       Gabriele Perego    10488414
--                  Christian Romeo    10629231
-- Create Date:     01.03.2021
-- Module Name:     project_reti_logiche
-- Project Name:    Prova Finale di Reti Logiche 2021
-- Teacher:         Gianluca Palermo - A.A. 2020/2021
-- Description:     Implementazione di un componente hardware descritto in VHDL che sviluppa una versione semplificata 
--                  dell'algoritmo di equalizzazione dell'istogramma di un' immagine in scala di grigi a 256 livelli.
--                  Il metodo è pensato per ricalibrare il contrasto di un' immagine effettuandone una distribuzione 
--                  su tutto l'intervallo di intensità, al fine di incrementare il contrasto quando 
--                  l'intervallo dei valori di intensità sono molto vicini.   
-----------------------------------------------------------------------------------------------------------------------
-- ############ COMPONENTE ############
library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;
use     IEEE.std_logic_unsigned.all;


entity project_reti_logiche is
    Port (                                              --  segnali input
           i_clk    : in  std_logic;                        -- Segnale di clock generato dal test bench.
           i_start  : in  std_logic;                        -- Segnale di start generato dal test bench. Il modulo parte nell'elaborazione quando il segnale START in ingresso viene portato a 1. Il segnale di START rimarrà alto fino a che il segnale di DONE non verrà portato alto.
           i_rst    : in  std_logic;                        -- Segnale di reset che inizializza la macchina pronta per ricevere il primo segnale di start.
           i_data   : in  std_logic_vector(7 downto 0);     -- Segnale che arriva dalla memoria in seguito ad una richiesta di lettura.
                                                        --  segnali output
           o_address: out std_logic_vector(15 downto 0);    -- Segnale che manda l'indirizzo alla memoria.
           o_done   : out std_logic;                        -- Segnale che comunica la fine dell'elaborazione e il dato di uscita in memoria. Il segnale DONE deve rimanere alto fino a che il segnale di START non è riportato a 0.
           o_en     : out std_logic;                        -- Segnale da dover mandare alla memoria per potere eseguire sia operazioni di lettura, sia di scrittura.
           o_we     : out std_logic;                        -- Segnale (HIGH) da dover mandare alla memoria per scriverci (LOW = lettura).
           o_data   : out std_logic_vector(7 downto 0)      -- Segnale da mandare alla memoria.
           );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is            

    -- ############ STATI DELLA FSM ############
type state is ( IDLE , RELOAD , WAIT_RAM , FETCH_DIM_COLUMN , FETCH_DIM_ROW , GET_MAX_MIN , CALC_SHIFT , EQUALIZE_READ , EQUALIZE_WRITE , DONE_HIGH , DONE_LOW );        
    
    -- ############ SEGNALI INTERNI DEL COMPONENTE ############
    signal state_cur, state_next : state;                                               --Segnali che tengono traccia dello stato prossimo che la FSM deve raggiungere. 
    signal o_address_cur         : std_logic_vector(15 downto 0) := "0000000000000000"; --Segnale di supporto ad o_address che contiene un indirizzo della RAM.
    signal new_pixel_value       : std_logic_vector(7 downto 0)  := "00000000";         --Segnale che contiene il nuovo valore del pixel equalizzato.  
    signal column , row          : integer range 0 to 128        := 0;                  --Segnali che contengono rispettivamente il numero di colonne e righe dell'immagine.                   
    signal max                   : integer range 0 to 255        := 0;                  --Segnale che contiene il massimo valore dei pixel dell'immagine.               
    signal min                   : integer range 0 to 255        := 255;                --Segnale che contiene il minimo valore dei pixel dell'immagine.
    signal shift_level           : integer                       := 0;                  --Segnale che contiene il valore SHIFT_LEVEL = (8 - FLOOR(LOG2(delta +1))).
                                          
  
begin

    -- ############ GESTIONE STATI ############
    process( i_clk , i_rst ,state_cur , i_data , i_start)  
         variable tmp: unsigned(7 downto 0);                                                                                                                
        begin
             if ( i_rst = '1' )then                                         --Appena viene ricevuto il segnale di reset si passa allo stato IDLE della macchina, dove vengono inizializzati i valori.                                       
                 state_cur <= IDLE;                                         
  
             elsif ( rising_edge(i_clk) )then                               --La sincronizzazione è impostata sul fronte di salita del clock.                     
       
             case state_cur is                                              --Descrizione degli stati della FSM, con il costrutto 'case' simulo il funzionamento della FSM.
                                                                            
    -- ############ STATO DI IDLE ############
                 when IDLE =>                                               -- @@ INIZIALIZZAZIONE @@
                          if ( i_start = '1')then                           --Appena viene ricevuto il segnale di start avviene l'inizializzazione della FSM.                  
                                state_next       <= FETCH_DIM_COLUMN;       --Si passa nello stato dove viene raccolto il numero di colonne dell'immagine.    
                                state_cur        <= WAIT_RAM;               --Stato che permette alla FSM di attendere un ciclo di clock aggiuntivo per riuscire ad osservare correttamente i cambiamenti in memoria.
                                o_en             <= '1';                    --Reset dei vari segnali utilizzati dalla FSM.
                                o_done           <= '0';                                     
                                o_we             <= '0';                    
                                max              <= 0;                                      
                                min              <= 255;                     
                                column           <= 0;                       
                                row              <= 0;                                           
                                o_address_cur    <= "0000000000000000";     --L'indirizzo sul quale viene letto il primo valore è ripristinato alla prima cella di lettura.
                                o_address        <= "0000000000000000";     --L'indirizzo che comunica con la memoria è settato a "0000000000000000".    
                          end if;
                  
    -- ############ STATO DI RELOAD ############              
                 when RELOAD =>                                                                                         -- @@ ATTESA E PREPARAZIONE SEGNALI @@                                         
                          state_cur              <= WAIT_RAM;                                                            
                                                                                                                         
                          if( state_next = EQUALIZE_READ )then                                                          --Se lo stato successivo è EQUALIZE_READ, attivo la lettura da memoria.                                                                                                                                                                             
                                                                                                                           
                          o_we                   <= '0';                                                                                                                               
                                if( o_address_cur /= std_logic_vector(to_unsigned( row * column + 2 , 16 )) )then       --eseguo le seguenti operazioni solo se non è la prima volta che viene chiamato EQUALIZE_READ e ciò coincide con o_address_cur essere all'indirizzo row*column+2                                                                                    --Se up='true' devo preparare l'inizio della lettura-scrittura dei pixel.                                                                                                                                        
                                o_address        <= std_logic_vector(unsigned(o_address_cur));                          --Si imposta la memoria all'inidirizzo di lettura del prossimo pixel salvato in o_address_cur.                                                                               
                                o_address_cur    <= std_logic_vector(unsigned(o_address_cur) + ( row * column ));       --Memorizzo l'indirizzo dove dovrò andare a scrivere il pixel equalizzato.                         
                                end if;                                                                                 
                                                                                                                                      
                          elsif( state_next = EQUALIZE_WRITE )then                                                                                                                                                                           
                                                                                                                                                                                    
                                o_we             <= '1';                                                                --Se lo stato successivo è EQUALIZE_WRITE, attivo la scrittura in memoria.                                                                                                                                      
                                o_address_cur    <= std_logic_vector(unsigned(o_address_cur) - ( row * column ) + 1);   --Memorizzo l'indirizzo della prossima lettura di pixel originale in o_address_cur        
                                o_address        <= std_logic_vector(unsigned(o_address_cur));                          --Si imposta la memoria all'inidirizzo di scrittura del pixel equalizzato.                        
                                                                                                                        
                          elsif( state_next = FETCH_DIM_ROW )then                                                                                                                                                                                                                            
                                                                                                                        
                                if( column = 0 )then                                                                    --Dopo aver letto il numero di colonne controllo che non sia nullo.                                                                          
                                state_cur       <= DONE_HIGH;                                                           -- in tal caso mi sposto nello stato di DONE_HIGH.
                                end if;
                                
                          elsif( state_next = GET_MAX_MIN )then                                                                                                                                                                           
                                                                                                                        
                                if( row = 0 )then                                                                       --Dopo aver letto il numero di righe controllo che non sia nullo                                                                       
                                state_cur        <= DONE_HIGH;                                                          -- in tal caso mi sposto nello stato di DONE_HIGH.        
                                end if;
                                
                          end if;
                          
    -- ############ STATO DI ATTESA ############                 
                when WAIT_RAM =>                                                        -- @@ SINCRONIZZAZIONE CLOCK - MEMORIA @@                                              
                          state_cur             <= state_next;                          --Stato in cui si sfrutta un ciclo di clock per aggiornare i segnali e poi si prosegue l'esecuzione. 

    -- ############ STATO DI FETCH_DIM_COLUMN ############                     
                when FETCH_DIM_COLUMN =>                                                -- @@ RACCOLTA NUMERO COLONNE @@
                          tmp := UNSIGNED(i_data);
                          column                <= to_integer(tmp);                     --Leggo dalla RAM il numero di colonne presente all'indirizzo "0000000000000000".                                                                                       
                          o_address             <= "0000000000000001";                  --Successivamente ci si prepara per l'eventuale lettura del numero di righe all'indirizzo successivo.
                          state_next            <= FETCH_DIM_row;                                            
                          state_cur             <= RELOAD;                          
                          

    -- ############ STATO DI FETCH_DIM_ROW ############     
                when FETCH_DIM_ROW =>                                                   -- @@ RACCOLTA NUMERO RIGHE @@                                                 
                          tmp := UNSIGNED(i_data);
                          row                    <= to_integer(tmp);                    --Leggo dalla RAM il numero di righe presente all'indirizzo "0000000000000001".                                 
                          o_address              <= "0000000000000010";                 --Successivamente ci si prepara per l'eventuale ricerca di massimo e minimo e perciò
                          o_address_cur          <= "0000000000000010";                 -- si impostano gli indirizzi al valore "0000000000000010", dove è contentuto il primo pixel dell'immagine di input.             
                          state_next             <= GET_MAX_MIN;                    
                          state_cur              <= RELOAD;                         

    -- ############ STATO DI GET_MAX_MIN ############
                when GET_MAX_MIN =>                                                                             -- @@ RICERCA MASSIMO E MINIMO VALORE DI PIXEL @@   
                          if( to_integer(UNSIGNED(i_data)) > max )then                  
                                max              <= to_integer(UNSIGNED(i_data));      
                          end if;                                                       
                          
                          if( to_integer(UNSIGNED(i_data)) < min )then              
                                min              <= to_integer(UNSIGNED(i_data));       
                          end if; 
                                        
                                o_address_cur    <= std_logic_vector(unsigned(o_address_cur) + 1);              --Memorizzo l'indirizzo seguente.  
                                o_address        <= o_address_cur;                                              --Assegno l'indirizzo *precedentemente* calcolato come seguente.   
                         
                          if( o_address_cur = std_logic_vector(to_unsigned( row * column + 2 , 16 )))then       --Si scorrono i pixel dell'immagine dal 3° al (row*column+2)°.      
                                state_next       <= CALC_SHIFT;                                                 --Una volta trovati massimo e minimo si passa al calcolo del Delta e Shift.
                                state_cur        <= RELOAD;                                                     
                          else                                                                             
                                state_next       <= GET_MAX_MIN;                                                --altrimenti si ritorna in questo stato dopo un ciclo di assestamento dei segnali.
                                state_cur        <= RELOAD;                                                            
                          end if;
                       

    -- ############ STATO DI CALCOLO SHIFT ############                         
                when CALC_SHIFT =>                                                                              -- @@ Calcolo il valore dello Shift da effettuare @@
                          if( (1<=( max - min ) + 1) and (( max - min ) + 1<2) )then                            --SHIFT_LEVEL = 8 - FLOOR(LOG2(delta +1)).
                                    shift_level           <= (8-0);                                             --calcoliamo lo shift utilizzando un metodo di controlli a soglia dove se il valore del delta 
                                elsif( (2<=( max - min ) + 1) and (( max - min ) + 1<4))then                    --rientra in certi range allora sappiamo a priori quanto varrà il floor del suo logaritmo base 2. 
                                    shift_level           <= (8-1);                                             
                                elsif( (4<=( max - min ) + 1) and (( max - min ) + 1<8))then
                                    shift_level           <= (8-2);
                                elsif( (8<=( max - min ) + 1) and (( max - min ) + 1<16))then
                                    shift_level           <= (8-3);
                                elsif( (16<=( max - min ) + 1) and (( max - min ) + 1<32))then
                                    shift_level           <= (8-4);
                                elsif( (32<=( max - min ) + 1) and (( max - min ) + 1<64))then
                                    shift_level           <= (8-5);
                                elsif( (64<=( max - min ) + 1) and (( max - min ) + 1<128))then
                                    shift_level           <= (8-6);
                                elsif( (128<=( max - min ) + 1) and (( max - min ) + 1<256))then
                                    shift_level           <= (8-7);
                                elsif( 256=( max - min ) + 1 )then
                                    shift_level           <= (8-8);
                          end if;
                          
                          state_next             <= EQUALIZE_READ;                                                                                            
                          state_cur              <= RELOAD;                                                     --Ci spostiamo ora nello stato di nuova lettura dei pixel originali, conoscendo lo shift level possiamo effettuare l'equalizzazione.                                                         
                          o_address_cur          <= std_logic_vector(to_unsigned( row * column + 2 , 16 ));     --A priori sappiamo che all'indirizzo row*column+2 avremo la prima cella vuota dove scrivere il primo pixel equalizzato.            
                          o_address              <= "0000000000000010";                                         --L'indirizzo di memoria servirà per la lettura del primo pixel originale, alla posizione 2.                                        

    -- ############ STATI DI EQUALIZZAZIONE ############
                when EQUALIZE_READ =>                                                                                                                                        -- @@ Calcolo il valore del pixel equalizzato da scrivere in uscita @@                        
                          if( std_logic_vector((to_unsigned(to_integer(UNSIGNED(i_data)) - min , 9 ) sll shift_level )) > std_logic_vector(to_unsigned( 254 , 9 )))then      --Controllo se il valore del pixel equalizzato supera il massimo valore della scala utilizzata, ovvero 255                                                         
                                new_pixel_value              <= std_logic_vector(to_unsigned( 255 , 8 ));                                                                    --In tal caso scrivo in output il valore massimo ammissibile, 255. 
                          else                                                                                                                                               -- n.b. abbiamo utilizzato 9 bit per il confronto seguiti dal fatto che il massimo valore possibile dopo il calcolo può essere maggiore di 254 ma comunque non supera mai 511.
                                new_pixel_value              <= std_logic_vector((to_unsigned(to_integer(UNSIGNED(i_data)) - min , 8 ) sll shift_level ));                   --Altrimenti scrivo il valore equalizzato tramite la formula (CURRENT_PIXEL_VALUE - MIN_PIXEL_VALUE) << SHIFT_LEVEL.      
                          end if;                                                                                                                                            --nb: i_data = CURRENT_PIXEL_VALUE.
                                                                                                                                                            
                          state_next             <= EQUALIZE_WRITE;                                                                                                          --Mi dirigo allo stato di scrittura del pixel equalizzato
                          state_cur              <= RELOAD;                                                                                                                  -- aggiornando gli indirizzi di scrittura nel RELOAD.

                when EQUALIZE_WRITE =>                                                                                  -- @@ Scrivo in memoria, di seguito all'immagine ricevuta, i nuovi pixel equalizzati @@                                                                
                                                                                                                        
                          o_data                 <= new_pixel_value;                                                    --nb: o_data scriverà dove si trova o_address.
                                                                                                                        
                          if( o_address_cur = std_logic_vector(to_unsigned( row * column + 2 , 16 )))then               --Se l'indirizzo da cui successivamente leggeremo il prossimo pixel originale è arrivato al valore (row*column)+2, l'immagine da equalizzare è stata terminata.
                                state_next       <= DONE_HIGH;                                                          --E quindi si passa allo stato DONE_HIGH.
                                state_cur        <= RELOAD;                                                             
                          else                                                                                                                                      
                                state_next       <= EQUALIZE_READ;                                                      --Altrimenti si ritorna allo stato di lettura pixel originali ma                                                                            
                                state_cur        <= RELOAD;                                                             -- non prima di aver aggiornato gli indirizzi di lettura nel RELOAD.                                                                                                                                                             
                          end if;    

    -- ############ STATI DI DONE ############                                                
                when DONE_HIGH =>                                                           -- @@ Congratulazioni hai equalizzato la tua prima immagine! @@ 
                          o_done                 <= '1';                                    --Alziamo il segnale o_done per segnalare il termine dell'operazione, e disabilitamo la lettura/scrittura da memoria
                          o_en                   <= '0';                                    -- la computazione è prossima al termine.
                          if ( i_start = '0' )then                                          -- SE E SOLO SE o_done è alto E i_start è basso, si procede a settare o_done a 0 nello stato di DONE_LOW
                                state_cur        <= DONE_LOW;                               -- altrimenti si rimane in questo stato anche nel prossimo ciclo, ad attendere che la condizione risulti vera.
                          end if;
                                                             
                when DONE_LOW =>                                                        
                          o_done                 <= '0';                                    --Viene abbassato anche o_done.
                          o_we                   <= '0';                                    
                          state_cur              <= IDLE;                                   -- Prossimo stato: IDLE, che riporta il componente allo stato iniziale,
                                                                                            -- siamo pronti per eseguire un'altra operazione.     
             end case;    
            end if;        
    end process;  
 
end Behavioral;