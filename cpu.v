///////////////////////////////////////////////////////////////////////////
// MODULE: CPU for TSC microcomputer: cpu.v
// Author: 
// Description: 

// DEFINITIONS
`define WORD_SIZE 16    // data and address word size

// MODULE DECLARATION
module cpu (
    output readM,                       // read from memory
    output [`WORD_SIZE-1:0] address,    // current address for data
    inout [`WORD_SIZE-1:0] data,        // data being input or output
    input inputReady,                   // indicates that data is ready from the input port
    input reset_n,                      // active-low RESET signal
    input clk,                          // clock signal

    // for debuging/testing purpose
    output [`WORD_SIZE-1:0] num_inst,   // number of instruction during execution
    output [`WORD_SIZE-1:0] output_port // this will be used for a "WWD" instruction
);

    reg [`WORD_SIZE-1:0] PC;
    reg [`WORD_SIZE-1:0] instruction;
    reg [`WORD_SIZE-1:0] num_inst_reg;
    reg [`WORD_SIZE-1:0] output_port_reg;

    assign num_inst    = num_inst_reg;
    assign output_port = output_port_reg;

    assign readM   = 1'b1;
    assign address = PC;
    assign data    = {`WORD_SIZE{1'bz}};   

    
    always @(posedge inputReady) begin
        instruction <= data;
    end

    wire RegWrite, ALUSrcB, RegDstSel, IsLHI, IsJMP, IsWWD;
    wire [`WORD_SIZE-1:0] next_PC, wwd_data;

    control_unit CU (
        .instruction(instruction),
        .RegWrite(RegWrite), .ALUSrcB(ALUSrcB), .RegDstSel(RegDstSel),
        .IsLHI(IsLHI), .IsJMP(IsJMP), .IsWWD(IsWWD)
    );

    datapath DP (
        .instruction(instruction), .PC(PC), .clk(clk), .reset_n(reset_n),
        .RegWrite(RegWrite), .ALUSrcB(ALUSrcB), .RegDstSel(RegDstSel),
        .IsLHI(IsLHI), .IsJMP(IsJMP),
        .next_PC(next_PC), .wwd_data(wwd_data)
    );

    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            PC              <= {`WORD_SIZE{1'b0}};
            num_inst_reg    <= {`WORD_SIZE{1'b0}};
            output_port_reg <= {`WORD_SIZE{1'b0}};
        end
        else begin
            PC           <= next_PC;
            num_inst_reg <= num_inst_reg + 16'h0001;
            if (IsWWD)
                output_port_reg <= wwd_data;
        end
    end

endmodule

module alu (
    input  [`WORD_SIZE-1:0] A,
    input  [`WORD_SIZE-1:0] B,
    output [`WORD_SIZE-1:0] result
);
    assign result = A + B;
endmodule



module register_file (
    input  [1:0] SA,              
    input  [1:0] SB,               
    input  [1:0] DR,               
    input  [`WORD_SIZE-1:0] D_in,  
    input  LD,                     
    input  clk,
    input  reset_n,
    output [`WORD_SIZE-1:0] DataA,
    output [`WORD_SIZE-1:0] DataB
);
    reg [`WORD_SIZE-1:0] regfile [0:3];
    integer i;

    assign DataA = regfile[SA];
    assign DataB = regfile[SB];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 4; i = i + 1)
                regfile[i] <= {`WORD_SIZE{1'b0}};
        end
        else if (LD) begin
            regfile[DR] <= D_in;
        end
    end
endmodule


module control_unit (
    input  [`WORD_SIZE-1:0] instruction,
    output reg RegWrite,    
    output reg ALUSrcB,     
    output reg RegDstSel,   
    output reg IsLHI,
    output reg IsJMP,
    output reg IsWWD
);
    wire [3:0] opcode = instruction[15:12];
    wire [5:0] func   = instruction[5:0];

    always @(*) begin
        RegWrite  = 1'b0;
        ALUSrcB   = 1'b0;
        RegDstSel = 1'b0;
        IsLHI     = 1'b0;
        IsJMP     = 1'b0;
        IsWWD     = 1'b0;

        case (opcode)
            4'b1111: begin 
                case (func)
                    6'b000000: begin 
                        RegWrite  = 1'b1;
                        ALUSrcB   = 1'b0;
                        RegDstSel = 1'b0;
                    end
                    6'b011100: begin 
                        IsWWD = 1'b1;
                    end
                    default: ; 
                endcase
            end
            4'b0100: begin 
                RegWrite  = 1'b1;
                ALUSrcB   = 1'b1;
                RegDstSel = 1'b1;
            end
            4'b0110: begin 
                RegWrite  = 1'b1;
                RegDstSel = 1'b1;
                IsLHI     = 1'b1;
            end
            4'b1001: begin 
                IsJMP = 1'b1;
            end
            default: ; 
        endcase
    end
endmodule



module datapath (
    input  [`WORD_SIZE-1:0] instruction,
    input  [`WORD_SIZE-1:0] PC,
    input  clk,
    input  reset_n,
    input  RegWrite,
    input  ALUSrcB,
    input  RegDstSel,
    input  IsLHI,
    input  IsJMP,
    output [`WORD_SIZE-1:0] next_PC,
    output [`WORD_SIZE-1:0] wwd_data
);
    wire [1:0]  rs     = instruction[11:10];
    wire [1:0]  rt     = instruction[9:8];
    wire [1:0]  rd     = instruction[7:6];
    wire [7:0]  imm8   = instruction[7:0];
    wire [11:0] target = instruction[11:0];

    wire [`WORD_SIZE-1:0] sign_ext_imm = {{8{imm8[7]}}, imm8};
    wire [1:0] write_addr = RegDstSel ? rt : rd;

    wire [`WORD_SIZE-1:0] DataA, DataB;
    wire [`WORD_SIZE-1:0] alu_B      = ALUSrcB ? sign_ext_imm : DataB;
    wire [`WORD_SIZE-1:0] alu_result;
    wire [`WORD_SIZE-1:0] write_data = IsLHI ? {imm8, 8'b0} : alu_result;

    register_file RF (
        .SA(rs), .SB(rt), .DR(write_addr), .D_in(write_data),
        .LD(RegWrite), .clk(clk), .reset_n(reset_n),
        .DataA(DataA), .DataB(DataB)
    );

    alu ALU0 (.A(DataA), .B(alu_B), .result(alu_result));

    assign wwd_data = DataA;                                  
    assign next_PC  = IsJMP ? {PC[15:12], target} : (PC + 16'h0001);
endmodule
