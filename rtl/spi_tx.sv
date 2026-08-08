
module spi_tx(
    input  logic        spi_tx_rstn,
    input  logic        spi_tx_ref_clk,
    input  logic [31:0] spi_tx_data,
    input  logic        spi_tx_clear,
    input  logic        spi_tx_sclk,
    input  logic        spi_tx_start,
    input  logic        spi_tx_fifo_empty,
    input  logic        spi_tx_cs,
    output logic        spi_tx_fifo_read_en,
    output logic        spi_tx_ready,
    output logic        spi_tx_mosi);

    integer i;
    logic [4:0]  cnt_reg;   //counts spi_tx_sclk egdes
    logic [31:0] data_reg;  //stores the data to be transmitted
    enum {idle, check, load, ready, await, prep, tran} state, next;
/*
    idle  - initial state, waiting for spi_tx_start = 1
    check - checking if tx_fifo has data
    load  - loading data from tx_fifo to data_reg
    prep  - waiting for spi_tx_cs to send msb before first edge of spi_tx_sclk
    tran  - waiting for first spi_tx_sclk edge and sending data data
*/

//region transitions
    always_comb begin
        case (state)
            idle    : next = (spi_tx_start) ? check : idle;
            check   : next = (spi_tx_stop)  ? idle  : (spi_tx_fifo_empty) ? load : check;
            load    : next = (spi_tx_stop)  ? idle  : prep;
            //ready   : next = (spi_tx_stop)  ? idle  : prep;
            prep    : next = (spi_tx_stop)  ? idle  : (spi_tx_cs)         ? prep : trans;
            trans   : next = (spi_tx_stop)  ? idle  : (cnt_reg == 5'd31)  ? (spi_tx_start) ? check : idle : trans;
            //trans   : next = (spi_tx_stop or (cnt_reg == 5'd31))  ? idle : trans;
            default : next = idle;
        endcase


    end
//endregion
//region states
    always_ff @(posedge spi_tx_ref_clk) begin
        if (spi_tx_rstn) begin
            state    <= idle;
            cnt_reg  <= 'h0;
            data_reg <= 'h0;
        end
        else if (!spi_tx_start) begin  //transmission is stopped, reset to idle state, reset cnt_reg
            state   <= idle;
            cnt_reg <= 'h0;
        end
        else if (spi_tx_clear) begin   //clear signal is set, reset to idle state, clear data
            state    <= idle;
            cnt_reg  <= 'h0;
            data_reg <= 'h0;
        end

        else begin
            state <= next;
            if (state == load) begin
                data_reg <= spi_tx_data;
                cnt_reg  <= 'h0;
            end
        end
    end
//endregion
//region output_logic
    always_ff @(posedge spi_tx_ref_clk) begin //setting spi_tx_ready and spi_tx_fifo_read_en for one spi_tx_ref_clk cycle
        if (state == check) begin
            spi_tx_fifo_read_en <= 1'b1;
        end
        else if (state == prep) begin    //spi_tx_ready can be set for more than one spi_tx_ref_clk cycle, because spi_rx_ready can be set later
        end
        else begin
            spi_tx_ready        <= 1'b0;
            spi_tx_fifo_read_en <= 1'b0;
        end
    end

    always_ff @(posedge spi_tx_sclk) begin                  //counting spi_tx_sclk edges
        if (state == trans) begin
            cnt_reg <= cnt_reg + 5'h1;
        end
        else begin
            cnt_reg <= cnt_reg;
        end
    end

    always_ff @(negedge spi_tx_sclk) begin
        if ((state == prep) and (!spi_tx_cs)) begin            //send msb before first edge of spi_tx_sclk
            spi_tx_mosi <= data_reg[31];
        end
        else if ((state == trans) and (cnt_reg < 5'd31)) begin //send data (except for msb) on spi_tx_mosi on negedge of spi_tx_sclk
            for (int i = 1; i < 31; i = i + cnt_reg) begin     //i = 1 because msb is sent in prep state before first edge of spi_tx_sclk
                spi_tx_mosi <= data_reg[31 - i];
            end
        end
        else begin
            spi_tx_mosi <= 'h0;
        end
    end
//endregion

endmodule
