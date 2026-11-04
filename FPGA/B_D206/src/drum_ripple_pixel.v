// Radially symmetric on an 8x8 panel: row/column serpentine and rotation do not
// change this shape. Bright core -> expanding coloured ring -> dim outer tail.
module drum_ripple_pixel(
    input wire [7:0] pixel_index,
    input wire [31:0] levels,phases,
    output reg [23:0] grb
);
    wire [2:0] x=pixel_index[2:0],y=pixel_index[5:3];
    wire [1:0] panel=pixel_index[7:6];
    reg [7:0] level,age,a,dim;
    reg [7:0] r,g,b;
    reg [6:0] d2;
    reg [1:0] ring,radius;
    function [5:0] square_distance;
        input [2:0] c;
        begin case(c)0,7:square_distance=49;1,6:square_distance=25;2,5:square_distance=9;default:square_distance=1;endcase end
    endfunction
    always @* begin
        level=(levels>>(panel*8));age=(phases>>(panel*8));
        d2={1'b0,square_distance(x)}+{1'b0,square_distance(y)};
        ring=(d2<=2) ? 0 : (d2<=18 ? 1 : (d2<=50 ? 2 : 3));
        radius=(age<8) ? age[2:1] : 3;
        r=0;g=0;b=0;a=0;dim=0;
        if(level!=0 && age<24) begin
            if(ring==radius) a=level;
            else if(ring<radius) a=(age<8) ? (level>>2) : (level>>3);
            // Four physical panel palettes: coral, cyan, violet, amber.
            dim=a>>1;
            case(panel)
                0:begin r=a;g=dim;end
                1:begin g=a;b=a;end
                2:begin r=dim;b=a;end
                3:begin r=a;g=dim;end
            endcase
            if(age<2 && ring==0) begin r=level;g=level;b=level;end
        end
        grb={g,r,b};
    end
endmodule
