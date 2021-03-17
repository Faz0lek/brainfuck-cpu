-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author: Martin Kostelník (xkoste12)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	signal CNT_out: std_logic_vector(7 downto 0);
	signal CNT_inc: std_logic;
	signal CNT_dec: std_logic;
	
	signal PC_out: std_logic_vector(12 downto 0);
	signal PC_inc: std_logic;
	signal PC_dec: std_logic;
	
	signal PTR_out: std_logic_vector(12 downto 0);
	signal PTR_inc: std_logic;
	signal PTR_dec: std_logic;
	
	signal sel1: std_logic;
	signal sel2: std_logic;
	signal MX2_out: std_logic_vector(12 downto 0);
	signal sel3: std_logic_vector(1 downto 0);
	
	type FSM is (s_init, s_fetch, s_decode,
				 s_incPtr1, s_incPtr2, s_decPtr1, s_decPtr2,
				 s_incVal, s_decVal,
				 s_put1, s_put2, s_get1, s_get2,
				 s_store1, s_store2, s_load1, s_load2,
				 s_loop1_start, s_loop2_start, s_loop3_start, s_loop4_start, s_loop5_start,
				 s_loop1_end, s_loop2_end, s_loop3_end, s_loop4_end, s_loop5_end,
				 s_halt, s_empty);
	signal state: FSM;
	signal nextState: FSM;
	
	type IType is (incPtr, decPtr, incVal, decVal, lPar, rPar, put, get, store, load, halt, empty);
	signal instruction: IType;

begin

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.
 
	CNT: process (RESET, CLK)
	begin
		if (RESET = '1') then
			CNT_out <= (others => '0');
		elsif (CLK'event) and (CLK = '1') then
			if (CNT_inc = '1') then
				CNT_out <= CNT_out + 1;
			elsif (CNT_dec = '1') then
				CNT_out <= CNT_out - 1;
			end if;
		end if;
	end process;
	
	PC: process (RESET, CLK)
	begin
		if (RESET = '1') then
			PC_out <= (others => '0');
		elsif (CLK'event) and (CLK = '1') then
			if (PC_inc = '1') then
				PC_out <= PC_out + 1;
			elsif (PC_dec = '1') then
				PC_out <= PC_out - 1;
			end if;
		end if;	
	end process;
	
	PTR: process(RESET, CLK)
	begin
		if (RESET = '1') then
			PTR_out <= "1000000000000";
		elsif (CLK'event) and (CLK = '1') then
			if (PTR_inc = '1') then
				if (PTR_out = "1111111111111") then
					PTR_out <= "1000000000000";
				else
					PTR_out <= PTR_out + 1;
				end if;
			elsif (PTR_dec = '1') then
				if (PTR_out = "1000000000000") then
					PTR_out <= "1111111111111";
				else
					PTR_out <= PTR_out - 1;
				end if;
			end if;
		end if;
	end process;
	
	MX1: process(CLK, sel1, PC_out, MX2_out)
	begin
		case sel1 is
			when '0' => DATA_ADDR <= MX2_out;
			when '1' => DATA_ADDR <= PC_out;
			when others =>
		end case;
	end process;
	
	MX2: process(CLK, sel2, PTR_out)
	begin
		case sel2 is
			when '0' => MX2_out <= PTR_out;
			when '1' => MX2_out <= "1000000000000";
			when others =>
		end case;
	end process;
	
	MX3: process(CLK, sel3, IN_DATA, DATA_RDATA)
	begin
		case sel3 is
			when "00" => DATA_WDATA <= IN_DATA;
			when "01" => DATA_WDATA <= DATA_RDATA + 1;
			when "10" => DATA_WDATA <= DATA_RDATA - 1;
			when "11" => DATA_WDATA <= DATA_RDATA;
			when others =>
		end case;
	end process;
	
	decoder: process(DATA_RDATA)
	begin
		case (DATA_RDATA) is
			when X"3E" => instruction <= incVal;
			when X"3C" => instruction <= decVal;
			when X"2B" => instruction <= incPtr;
			when X"2D" => instruction <= decPtr;
			when X"5B" => instruction <= lPar;
			when X"5D" => instruction <= rPar;
			when X"2E" => instruction <= put;
			when X"2C" => instruction <= get;
			when X"24" => instruction <= store;
			when X"21" => instruction <= load;
			when X"00" => instruction <= halt;
			when others => instruction <= empty;
		end case;
	end process;
	
	FSM_state: process(RESET, CLK)
	begin
		if (RESET = '1') then
			state <= s_init;
		elsif (CLK'event) and (CLK = '1') then
			if (EN = '1') then
				state <= nextState;
			end if;
		end if;
	end process;
	
	FSM_nextState: process(IN_VLD, IN_DATA, DATA_RDATA, OUT_BUSY, state, instruction, CNT_out, sel1, sel2)
	begin
	
		CNT_inc   <= '0';
		CNT_dec   <= '0';
		PC_inc    <= '0';
		PC_dec    <= '0';
		PTR_inc   <= '0';
		PTR_dec   <= '0';
		
		DATA_EN   <= '0';
		DATA_RDWR <= '0';
		
		IN_REQ    <= '0';
		OUT_WE    <= '0';
		
		sel2	    <= '0';
		sel3		 <= "11";
		
		case state is
			when (s_init) =>
				nextState <= s_fetch;
				
			when (s_fetch) =>
				nextState <= s_decode;
				DATA_EN <= '1';
				sel1 <= '1';
			
			when (s_decode) =>
				case (instruction) is
					when (incPtr) =>
						nextState <= s_incPtr1;
						
					when (decPtr) =>
						nextState <= s_decPtr1;
						
					when (incVal) =>
						nextState <= s_incVal;
						
					when (decVal) =>
						nextState <= s_decVal;
						
					when (lPar) =>
						nextState <= s_loop1_start;
						
					when (rPar) =>
						nextState <= s_loop1_end;
						
					when (put) =>
						nextState <= s_put1;
						
					when (get) =>
						nextState <= s_get1;
						
					when (store) =>
						nextState <= s_store1;
						
					when (load) =>
						nextState <= s_load1;
						
					when (halt) =>
						nextState <= s_halt;

					when others =>
						nextState <= s_empty;
				end case;
				
			when (s_incPtr1) =>
				nextState <= s_incPtr2;
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				sel1 <= '0';
				
			when (s_incPtr2) =>
				nextState <= s_fetch;
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				sel1 <= '0';
				sel3 <= "01";
				PC_inc <= '1';
			
			when (s_decPtr1) =>
				nextState <= s_decPtr2;
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				sel1 <= '0';
				
			when (s_decPtr2) =>
				nextState <= s_fetch;
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				sel1 <= '0';
				sel3 <= "10";
				PC_inc <= '1';
				
			when (s_incVal) =>
				nextState <= s_fetch;
				PTR_inc <= '1';
				PC_inc <= '1';
				
			when (s_decVal) =>
				nextState <= s_fetch;
				PTR_dec <= '1';
				PC_inc <= '1';
				
			when (s_put1) =>
				nextState <= s_put2;
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				sel1 <= '0';
				
			when (s_put2) =>
				nextState <= s_put2;
				
				if (OUT_BUSY = '0') then
					nextState <= s_fetch;
					OUT_WE <= '1';
					OUT_DATA <= DATA_RDATA;
					PC_inc <= '1';
				end if;
			
			when (s_get1) =>
				nextState <= s_get2;
				IN_REQ <= '1';
				
			when (s_get2) =>
				nextState <= s_get2;
				IN_REQ <= '1';
				
				if (IN_VLD = '1') then
					nextState <= s_fetch;
					DATA_EN <= '1';
					DATA_RDWR <= '1';
					sel1 <= '0';
					sel3 <= "00";
					PC_inc <= '1';
				end if;
				
			when (s_store1) =>
				nextState <= s_store2;
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				sel1 <= '0';
				sel2 <= '0';
				
			when (s_store2) =>
				nextState <= s_fetch;
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				sel1 <= '0';
				sel2 <= '1';
				sel3 <= "11";
				PC_inc <= '1';
				
			when (s_load1) =>
				nextState <= s_load2;
				sel1 <= '0';
				sel2 <= '1';
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				
			when (s_load2) =>
				nextState <= s_fetch;
				sel1 <= '0';
				sel2 <= '0';
				sel3 <= "11";
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				PC_inc <= '1';
			
			when (s_loop1_start) =>
				nextState <= s_loop2_start;
				DATA_EN <= '1';
				PC_inc <= '1';
				sel1 <= '0';
				DATA_RDWR <= '0';
				
			when (s_loop2_start) =>
				nextState <= s_fetch;
				
				if (DATA_RDATA = "00000000") then
					nextState <= s_loop3_start;
					CNT_inc <= '1';
				end if;
				
			when (s_loop3_start) =>
				nextState <= s_loop4_start;
				DATA_EN <= '1';
				sel1 <= '1';
				
			when (s_loop4_start) =>
				nextState <= s_loop5_start;
				PC_inc <= '1';	
				
				if (instruction = lPar) then
					CNT_inc <= '1';
				elsif (instruction = rPar) then
					CNT_dec <= '1';
				end if;
				
			when (s_loop5_start) =>
				nextState <= s_loop3_start;
				
				if (CNT_out = "00000000") then
					nextState <= s_fetch;
				end if;
				
			when (s_loop1_end) =>
				nextState <= s_loop2_end;
				DATA_EN <= '1';
				sel1 <= '0';
				DATA_RDWR <= '0';
				
			when (s_loop2_end) =>
				nextState <= s_fetch;
				
				if (DATA_RDATA = "00000000") then
					PC_inc <= '1';
				else
					nextState <= s_loop3_end;
					PC_dec <= '1';
					CNT_inc <= '1';
				end if;
				
			when (s_loop3_end) =>
				nextState <= s_loop4_end;
				DATA_EN <= '1';
				sel1 <= '1';
				
			when (s_loop4_end) =>
				nextState <= s_loop5_end;
				
				if (instruction = lPar) then
					CNT_dec <= '1';
				elsif (instruction = rPar) then
					CNT_inc <= '1';
				end if;
				
			when (s_loop5_end) =>
				nextState <= s_fetch;
				
				if (CNT_out = "00000000") then
					PC_inc <= '1';
				else
					nextState <= s_loop3_end;
					PC_dec <= '1';
				end if;	
			
			when (s_halt) =>
				nextState <= s_halt;
				
			when (s_empty) =>
				nextState <= s_fetch;
				PC_inc <= '1';
			
			when others =>
		end case;
	end process;
end behavioral;
