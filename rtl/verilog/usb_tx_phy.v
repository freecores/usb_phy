/////////////////////////////////////////////////////////////////////
////                                                             ////
////  USB 1.1 PHY                                                ////
////  TX                                                         ////
////                                                             ////
////                                                             ////
////  Author: Rudolf Usselmann                                   ////
////          rudi@asics.ws                                      ////
////                                                             ////
////                                                             ////
////  Downloaded from: http://www.opencores.org/cores/usb_phy/   ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2000-2002 Rudolf Usselmann                    ////
////                         www.asics.ws                        ////
////                         rudi@asics.ws                       ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////

//  CVS Log
//
//  $Id: usb_tx_phy.v,v 1.1.1.1 2002-09-16 14:27:02 rudi Exp $
//
//  $Date: 2002-09-16 14:27:02 $
//  $Revision: 1.1.1.1 $
//  $Author: rudi $
//  $Locker:  $
//  $State: Exp $
//
// Change History:
//               $Log: not supported by cvs2svn $
//
//
//
//
//
//

`include "timescale.v"

module usb_tx_phy(
		clk, rst, fs_ce, phy_mode,
	
		// Transciever Interface
		txdp, txdn, txoe,	

		// UTMI Interface
		DataOut_i, TxValid_i, TxReady_o
		);

input		clk;
input		rst;
input		fs_ce;
input		phy_mode;
output		txdp, txdn, txoe;
input	[7:0]	DataOut_i;
input		TxValid_i;
output		TxReady_o;

///////////////////////////////////////////////////////////////////
//
// Local Wires and Registers
//

parameter	IDLE	= 3'd0,
		SOP	= 3'h1,
		DATA	= 3'h2,
		EOP1	= 3'h3,
		EOP2	= 3'h4,
		WAIT	= 3'h5;

reg		TxReady_o;
reg	[2:0]	state, next_state;
reg		tx_ready;
reg		tx_ready_d;
reg		ld_sop_d;
reg		ld_data_d;
reg		ld_eop_d;
reg		tx_ip;
reg		tx_ip_sync;
reg	[2:0]	bit_cnt;
reg	[7:0]	hold_reg;
reg		sd_raw_o;
wire		hold;
reg		data_done;
reg		sft_done;
reg		sft_done_r;
wire		sft_done_e;
reg		ld_data;
wire		eop_done;
reg	[2:0]	one_cnt;
wire		stuff;
reg		sd_bs_o;
reg		sd_nrzi_o;
reg		append_eop;
reg		append_eop_sync1;
reg		append_eop_sync2;
reg		append_eop_sync3;
reg		txdp, txdn;
reg		txoe_r1, txoe_r2;
reg		txoe;

///////////////////////////////////////////////////////////////////
//
// Misc Logic
//

always @(posedge clk)
	tx_ready <= #1 tx_ready_d;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	TxReady_o <= #1 1'b0;
	else		TxReady_o <= #1 tx_ready_d & TxValid_i;

always @(posedge clk)
	ld_data <= #1 ld_data_d;

///////////////////////////////////////////////////////////////////
//
// Transmit in progress indicator
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	tx_ip <= #1 1'b0;
	else
	if(ld_sop_d)	tx_ip <= #1 1'b1;
	else
	if(eop_done)	tx_ip <= #1 1'b0;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		tx_ip_sync <= #1 1'b0;
	else
	if(fs_ce)		tx_ip_sync <= #1 tx_ip;

// data_done helps us to catch cases where TxValid drops due to
// packet end and then gets re-asserted as a new packet starts.
// We might not see this because we are still transmitting.
// data_done should solve those cases ...
`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		data_done <= #1 1'b0;
	else
	if(TxValid_i & ! tx_ip)	data_done <= #1 1'b1;
	else
	if(!TxValid_i)		data_done <= #1 1'b0;

///////////////////////////////////////////////////////////////////
//
// Shift Register
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		bit_cnt <= #1 3'h0;
	else
	if(!tx_ip_sync)		bit_cnt <= #1 3'h0;
	else
	if(fs_ce & !hold)	bit_cnt <= #1 bit_cnt + 3'h1;

assign hold = stuff;

always @(posedge clk)
	if(!tx_ip_sync)		sd_raw_o <= #1 1'b0;
	else
	case(bit_cnt)	// synopsys full_case parallel_case
	   3'h0: sd_raw_o <= #1 hold_reg[0];
	   3'h1: sd_raw_o <= #1 hold_reg[1];
	   3'h2: sd_raw_o <= #1 hold_reg[2];
	   3'h3: sd_raw_o <= #1 hold_reg[3];
	   3'h4: sd_raw_o <= #1 hold_reg[4];
	   3'h5: sd_raw_o <= #1 hold_reg[5];
	   3'h6: sd_raw_o <= #1 hold_reg[6];
	   3'h7: sd_raw_o <= #1 hold_reg[7];
	endcase

always @(posedge clk)
	sft_done <= #1 !hold & (bit_cnt == 3'h7);

always @(posedge clk)
	sft_done_r <= #1 sft_done;

assign sft_done_e = sft_done & !sft_done_r;

// Out Data Hold Register
always @(posedge clk)
	if(ld_sop_d)	hold_reg <= #1 8'h80;
	else
	if(ld_data)	hold_reg <= #1 DataOut_i;

///////////////////////////////////////////////////////////////////
//
// Bit Stuffer
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	one_cnt <= #1 3'h0;
	else
	if(!tx_ip_sync)	one_cnt <= #1 3'h0;
	else
	if(fs_ce)
	   begin
		if(!sd_raw_o | stuff)	one_cnt <= #1 3'h0;
		else			one_cnt <= #1 one_cnt + 3'h1;
	   end

assign stuff = (one_cnt==3'h6);

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	sd_bs_o <= #1 1'h0;
	else
	if(fs_ce)	sd_bs_o <= #1 !tx_ip_sync ? 1'b0 :
				(stuff ? 1'b0 : sd_raw_o);

///////////////////////////////////////////////////////////////////
//
// NRZI Encoder
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	sd_nrzi_o <= #1 1'b1;
	else
	if(!tx_ip_sync | !txoe_r1)	sd_nrzi_o <= #1 1'b1;
	else
	if(fs_ce)	sd_nrzi_o <= #1 sd_bs_o ? sd_nrzi_o : ~sd_nrzi_o;

///////////////////////////////////////////////////////////////////
//
// EOP append logic
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		append_eop <= #1 1'b0;
	else
	if(ld_eop_d)		append_eop <= #1 1'b1;
	else
	if(append_eop_sync2)	append_eop <= #1 1'b0;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	append_eop_sync1 <= #1 1'b0;
	else
	if(fs_ce)	append_eop_sync1 <= #1 append_eop;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	append_eop_sync2 <= #1 1'b0;
	else
	if(fs_ce)	append_eop_sync2 <= #1 append_eop_sync1;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	append_eop_sync3 <= #1 1'b0;
	else
	if(fs_ce)	append_eop_sync3 <= #1 append_eop_sync2;

assign eop_done = append_eop_sync3;

///////////////////////////////////////////////////////////////////
//
// Output Enable Logic
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	txoe_r1 <= #1 1'b0;
	else
	if(fs_ce)	txoe_r1 <= #1 tx_ip_sync;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	txoe_r2 <= #1 1'b0;
	else
	if(fs_ce)	txoe_r2 <= #1 txoe_r1;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	txoe <= #1 1'b1;
	else
	if(fs_ce)	txoe <= #1 !(txoe_r1 | txoe_r2);

///////////////////////////////////////////////////////////////////
//
// Output Registers
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	txdp <= #1 1'b1;
	else
	if(fs_ce)	txdp <= #1 phy_mode ?
					(!append_eop_sync3 &  sd_nrzi_o) :
					sd_nrzi_o;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	txdn <= #1 1'b0;
	else
	if(fs_ce)	txdn <= #1 phy_mode ?
					(!append_eop_sync3 & ~sd_nrzi_o) :
					append_eop_sync3;

///////////////////////////////////////////////////////////////////
//
// Tx Statemashine
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	state <= #1 IDLE;
	else		state <= #1 next_state;

always @(state or TxValid_i or data_done or sft_done_e or eop_done or fs_ce)
   begin
	next_state = state;
	tx_ready_d = 1'b0;

	ld_sop_d = 1'b0;
	ld_data_d = 1'b0;
	ld_eop_d = 1'b0;

	case(state)	// synopsys full_case parallel_case
	   IDLE:
		   begin
			if(TxValid_i)
			   begin
				ld_sop_d = 1'b1;
				next_state = SOP;
			   end
		   end
	   SOP:
		   begin
			if(sft_done_e)
			   begin
				tx_ready_d = 1'b1;
				ld_data_d = 1'b1;
				next_state = DATA;
			   end
		   end
	   DATA:
		   begin
			if(!data_done & sft_done_e)
			   begin
				ld_eop_d = 1'b1;
				next_state = EOP1;
			   end
			
			if(data_done & sft_done_e)
			   begin
				tx_ready_d = 1'b1;
				ld_data_d = 1'b1;
			   end
		   end
	   EOP1:
		   begin
			if(eop_done)		next_state = EOP2;
		   end
	   EOP2:
		   begin
			if(!eop_done & fs_ce)	next_state = WAIT;
		   end
	   WAIT:
		   begin
			if(fs_ce)		next_state = IDLE;
		   end
	endcase
	
   end

endmodule

