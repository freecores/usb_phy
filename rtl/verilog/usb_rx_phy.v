/////////////////////////////////////////////////////////////////////
////                                                             ////
////  USB 1.1 PHY                                                ////
////  RX & DPLL                                                  ////
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
//  $Id: usb_rx_phy.v,v 1.1.1.1 2002-09-16 14:27:01 rudi Exp $
//
//  $Date: 2002-09-16 14:27:01 $
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
//

`include "timescale.v"

module usb_rx_phy(	clk, rst, fs_ce,
	
			// Transciever Interface
			rxd, rxdp, rxdn,

			// UTMI Interface
			RxValid_o, RxActive_o, RxError_o, DataIn_o,
			RxEn_i, LineState);

input		clk;
input		rst;
output		fs_ce;
input		rxd, rxdp, rxdn;
output	[7:0]	DataIn_o;
output		RxValid_o;
output		RxActive_o;
output		RxError_o;
input		RxEn_i;
output	[1:0]	LineState;

///////////////////////////////////////////////////////////////////
//
// Local Wires and Registers
//

reg		rxd_t1,  rxd_s1,  rxd_s;
reg		rxdp_t1, rxdp_s1, rxdp_s;
reg		rxdn_t1, rxdn_s1, rxdn_s;
reg		synced_d;
wire		k, j, se0;
reg		rx_en;
reg		rx_active;
reg	[2:0]	bit_cnt;
reg		rx_valid1, rx_valid;
reg		shift_en;
reg		sd_r;
reg		sd_nrzi;
reg	[7:0]	hold_reg;
wire		drop_bit;	// Indicates a stuffed bit
reg	[2:0]	one_cnt;

reg	[1:0]	dpll_state, dpll_next_state;
reg		fs_ce_d, fs_ce;
wire		change;
reg		rxdp_s1r, rxdn_s1r;
wire		lock_en;
reg		fs_ce_r1, fs_ce_r2, fs_ce_r3;
reg	[2:0]	fs_state, fs_next_state;
reg		rx_valid_r;

///////////////////////////////////////////////////////////////////
//
// Misc Logic
//

assign RxActive_o = rx_active;
assign RxValid_o = rx_valid;
assign RxError_o = 0;
assign DataIn_o = hold_reg;
assign LineState = {rxdp_s1, rxdn_s1};

always @(posedge clk)
	rx_en <= #1 RxEn_i;

///////////////////////////////////////////////////////////////////
//
// Synchronize Inputs
//

// First synchronize to the local system clock to
// avoid metastability outside the sync block (*_s1)
// Second synchronise to the internal bit clock (*_s)
always @(posedge clk)
	rxd_t1 <= #1 rxd;

always @(posedge clk)
	rxd_s1 <= #1 rxd_t1;

always @(posedge clk)
	rxd_s <= #1 rxd_s1;

always @(posedge clk)
	rxdp_t1 <= #1 rxdp;

always @(posedge clk)
	rxdp_s1 <= #1 rxdp_t1;

always @(posedge clk)
	rxdp_s <= #1 rxdp_s1;

always @(posedge clk)
	rxdn_t1 <= #1 rxdn;

always @(posedge clk)
	rxdn_s1 <= #1 rxdn_t1;

always @(posedge clk)
	rxdn_s <= #1 rxdn_s1;

assign k = !rxdp_s &  rxdn_s;
assign j =  rxdp_s & !rxdn_s;
assign se0 = !rxdp_s & !rxdn_s;

///////////////////////////////////////////////////////////////////
//
// DPLL
//

// This design uses a clock enable to do 12Mhz timing and not a
// real 12Mhz clock. Everything always runs at 48Mhz. We want to
// make sure however, that the clock enable is always exactly in
// the middle between two virtual 12Mhz rising edges.
// We monitor rxdp and rxdn for any changes and do the appropiate
// adjustments.
// In addition to the locking done in the dpll FSM, we adjust the
// final latch enable to compensate for various sync registers ...

// Allow lockinf only when we are receiving
assign	lock_en = rx_en;

// Edge detector
always @(posedge clk)
	rxdp_s1r <= #1 rxdp_s1;

always @(posedge clk)
	rxdn_s1r <= #1 rxdn_s1;

assign change = (rxdp_s1r != rxdp_s1) | (rxdn_s1r != rxdn_s1);

// DPLL FSM
`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	dpll_state <= #1 2'h1;
	else		dpll_state <= #1 dpll_next_state;

always @(dpll_state or lock_en or change)
   begin
	fs_ce_d = 1'b0;
	case(dpll_state)	// synopsys full_case parallel_case
	   2'h0:
		if(lock_en & change)	dpll_next_state = 3'h0;
		else			dpll_next_state = 3'h1;
	   2'h1:begin
		fs_ce_d = 1'b1;
		//if(lock_en & change)	dpll_next_state = 3'h0;
		if(lock_en & change)	dpll_next_state = 3'h3;
		else			dpll_next_state = 3'h2;
		end
	   2'h2:
		if(lock_en & change)	dpll_next_state = 3'h0;
		else			dpll_next_state = 3'h3;
	   2'h3:
		if(lock_en & change)	dpll_next_state = 3'h0;
		else			dpll_next_state = 3'h0;
	endcase
   end

// Compensate for sync registers at the input - allign full speed
// clock enable to be in the middle between two bit changes ...
always @(posedge clk)
	fs_ce_r1 <= #1 fs_ce_d;

always @(posedge clk)
	fs_ce_r2 <= #1 fs_ce_r1;

always @(posedge clk)
	fs_ce_r3 <= #1 fs_ce_r2;

always @(posedge clk)
	fs_ce <= #1 fs_ce_r3;

///////////////////////////////////////////////////////////////////
//
// Find Sync Pattern FSM
//

parameter	FS_IDLE	= 3'h0,
		K1	= 3'h1,
		J1	= 3'h2,
		K2	= 3'h3,
		J2	= 3'h4,
		K3	= 3'h5,
		J3	= 3'h6,
		K4	= 3'h7;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	fs_state <= #1 FS_IDLE;
	else		fs_state <= #1 fs_next_state;

always @(fs_state or fs_ce or k or j or rx_en)
   begin
	synced_d = 1'b0;
	fs_next_state = fs_state;
	if(fs_ce)
	   case(fs_state)	// synopsys full_case parallel_case
		FS_IDLE:
		     begin
			if(k & rx_en)	fs_next_state = K1;
		     end
		K1:
		     begin
			if(j & rx_en)	fs_next_state = J1;
			else		fs_next_state = FS_IDLE;
		     end
		J1:
		     begin
			if(k & rx_en)	fs_next_state = K2;
			else		fs_next_state = FS_IDLE;
		     end
		K2:
		     begin
			if(j & rx_en)	fs_next_state = J2;
			else		fs_next_state = FS_IDLE;
		     end
		J2:
		     begin
			if(k & rx_en)	fs_next_state = K3;
			else		fs_next_state = FS_IDLE;
		     end
		K3:
		     begin
			if(j & rx_en)	fs_next_state = J3;
			else
			if(k & rx_en)	fs_next_state = K4;	// Allow missing one J
			else		fs_next_state = FS_IDLE;
		     end
		J3:
		     begin
			if(k & rx_en)	fs_next_state = K4;
			else		fs_next_state = FS_IDLE;
		     end
		K4:
		     begin
			if(k)	synced_d = 1'b1;
			fs_next_state = FS_IDLE;
		     end
	   endcase
   end

///////////////////////////////////////////////////////////////////
//
// Generate RxActive
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		rx_active <= #1 1'b0;
	else
	if(synced_d & rx_en)	rx_active <= #1 1'b1;
	else
	if(se0 & rx_valid_r )	rx_active <= #1 1'b0;

always @(posedge clk)
	if(rx_valid)	rx_valid_r <= #1 1'b1;
	else
	if(fs_ce)	rx_valid_r <= #1 1'b0;

///////////////////////////////////////////////////////////////////
//
// NRZI Decoder
//

always @(posedge clk)
	if(fs_ce)	sd_r <= #1 rxd_s;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		sd_nrzi <= #1 1'b0;
	else
	if(rx_active & fs_ce)	sd_nrzi <= #1 !(rxd_s ^ sd_r);

///////////////////////////////////////////////////////////////////
//
// Bit Stuff Detect
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)	one_cnt <= #1 3'h0;
	else
	if(!shift_en)	one_cnt <= #1 3'h0;
	else
	if(fs_ce)
	   begin
		if(!sd_nrzi | drop_bit)	one_cnt <= #1 3'h0;
		else			one_cnt <= #1 one_cnt + 3'h1;
	   end

assign drop_bit = (one_cnt==3'h6);

///////////////////////////////////////////////////////////////////
//
// Serial => Parallel converter
//

always @(posedge clk)
	if(fs_ce)	shift_en <= #1 synced_d | rx_active;

always @(posedge clk)
	if(fs_ce & shift_en & !drop_bit)
		hold_reg <= #1 {sd_nrzi, hold_reg[7:1]};

///////////////////////////////////////////////////////////////////
//
// Generate RxValid
//

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)		bit_cnt <= #1 3'b0;
	else
	if(!shift_en)		bit_cnt <= #1 3'h0;
	else
	if(fs_ce & !drop_bit)	bit_cnt <= #1 bit_cnt + 3'h1;

`ifdef USB_ASYNC_REST
always @(posedge clk or negedge rst)
`else
always @(posedge clk)
`endif
	if(!rst)				rx_valid1 <= #1 1'b0;
	else
	if(fs_ce & !drop_bit & (bit_cnt==3'h7))	rx_valid1 <= #1 1'b1;
	else
	if(rx_valid1 & fs_ce & !drop_bit)	rx_valid1 <= #1 1'b0;

always @(posedge clk)
	rx_valid <= #1 !drop_bit & rx_valid1 & fs_ce;

endmodule

