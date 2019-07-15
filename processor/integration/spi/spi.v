module spi;
  reg [8-1:0] tx_fifo; reg [3:0] tx_fifo_len = 0;
  reg [8-1:0] rx_fifo; reg [3:0] rx_fifo_len = 0;
  reg sck = 0;

  task automatic cycle;
    input miso;
    output sck_out, mosi;
  begin:cycle
    if (tx_fifo_len) begin
      if (sck) begin
        tx_fifo = {tx_fifo, 1'bx};
        tx_fifo_len = tx_fifo_len - 1;
      end else begin
        rx_fifo = {rx_fifo[6:0], miso};
        rx_fifo_len = rx_fifo_len + 1;
      end
      sck = ~sck;
    end

    sck_out = sck; mosi = tx_fifo[7];
  end endtask

  task automatic write;
    input [7:0] data;
    output err;
  begin:write
    if (!tx_fifo_len) begin
      tx_fifo = data;
      tx_fifo_len = 8;
      err = 0;
    end else begin
      err = 1;
    end
  end endtask

  task automatic read;
    output [7:0] data;
    output err;
  begin:write
    if (rx_fifo_len == 8) begin
      data = rx_fifo;
      rx_fifo_len = 0;
      err = 0;
    end else begin
      err = 1;
    end
  end endtask

endmodule

module spi_test;
  spi spi();

  initial begin : initial_
    integer i;
    reg err;

    reg miso, sck, mosi;
    miso = 0; sck = 0; mosi = 0;

    $dumpfile("spi.vcd");
    $dumpvars(1, sck, mosi, miso);

    spi.write(8'h5a, err);
    $display("%b", err);
    for (i = 0; i < 20; i = i + 1) begin : for_
      #1
      spi.cycle(miso,
        sck, mosi);
      miso = mosi;
      $display("%x %x %x", miso, sck, mosi);
    end
    begin:_
      reg [7:0] read_result; reg read_err;
      spi.read(read_result, read_err);
      $display("%x %x", read_result, read_err);
    end
  end
endmodule
