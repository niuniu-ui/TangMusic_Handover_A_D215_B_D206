`timescale 1ns/1ps
// Clean fundamental-led voice with gentle breath-dependent harmonics.
// No synthetic air/onset noise; phase remains continuous across G2-C#6.
module flute_voice #(parameter integer CLK_HZ=21000000,FRAME_CYCLES=512,
    ATTACK_MS=12,RELEASE_MS=32)(
    input wire clk,rst_n,sample_ce,gate,input wire [7:0] gain,
    input wire [6:0] note,input wire pure_tone,output reg signed [15:0] pcm
);
    localparam integer SAMPLE_HZ=(CLK_HZ+FRAME_CYCLES/2)/FRAME_CYCLES;
    localparam [15:0] ATTACK_STEP=(16320*1000+SAMPLE_HZ*ATTACK_MS-1)/(SAMPLE_HZ*ATTACK_MS);
    localparam [15:0] RELEASE_STEP=(16320*1000+SAMPLE_HZ*RELEASE_MS-1)/(SAMPLE_HZ*RELEASE_MS);
    reg [31:0] phase,increment;
    reg [15:0] amplitude;
    reg signed [20:0] body_mix;
    wire [15:0] target=gate ? {2'b0,gain,6'b0} : 16'd0;
    wire [7:0] brightness=amplitude[13:6];
    function [31:0] tuning;
        input [31:0] milli_hz;
        begin tuning=(64'd4294967296*FRAME_CYCLES*milli_hz+64'd500*CLK_HZ)/(64'd1000*CLK_HZ);end
    endfunction
    reg signed [15:0] sine_table[0:255];
    initial begin
        sine_table[0]=16'sd0;
        sine_table[1]=16'sd294;
        sine_table[2]=16'sd589;
        sine_table[3]=16'sd883;
        sine_table[4]=16'sd1176;
        sine_table[5]=16'sd1469;
        sine_table[6]=16'sd1761;
        sine_table[7]=16'sd2052;
        sine_table[8]=16'sd2341;
        sine_table[9]=16'sd2629;
        sine_table[10]=16'sd2916;
        sine_table[11]=16'sd3201;
        sine_table[12]=16'sd3483;
        sine_table[13]=16'sd3764;
        sine_table[14]=16'sd4043;
        sine_table[15]=16'sd4319;
        sine_table[16]=16'sd4592;
        sine_table[17]=16'sd4863;
        sine_table[18]=16'sd5131;
        sine_table[19]=16'sd5395;
        sine_table[20]=16'sd5657;
        sine_table[21]=16'sd5915;
        sine_table[22]=16'sd6169;
        sine_table[23]=16'sd6420;
        sine_table[24]=16'sd6667;
        sine_table[25]=16'sd6910;
        sine_table[26]=16'sd7148;
        sine_table[27]=16'sd7383;
        sine_table[28]=16'sd7613;
        sine_table[29]=16'sd7838;
        sine_table[30]=16'sd8059;
        sine_table[31]=16'sd8274;
        sine_table[32]=16'sd8485;
        sine_table[33]=16'sd8691;
        sine_table[34]=16'sd8891;
        sine_table[35]=16'sd9087;
        sine_table[36]=16'sd9276;
        sine_table[37]=16'sd9460;
        sine_table[38]=16'sd9638;
        sine_table[39]=16'sd9811;
        sine_table[40]=16'sd9978;
        sine_table[41]=16'sd10138;
        sine_table[42]=16'sd10293;
        sine_table[43]=16'sd10441;
        sine_table[44]=16'sd10583;
        sine_table[45]=16'sd10719;
        sine_table[46]=16'sd10848;
        sine_table[47]=16'sd10971;
        sine_table[48]=16'sd11087;
        sine_table[49]=16'sd11196;
        sine_table[50]=16'sd11299;
        sine_table[51]=16'sd11394;
        sine_table[52]=16'sd11483;
        sine_table[53]=16'sd11565;
        sine_table[54]=16'sd11640;
        sine_table[55]=16'sd11708;
        sine_table[56]=16'sd11769;
        sine_table[57]=16'sd11823;
        sine_table[58]=16'sd11870;
        sine_table[59]=16'sd11910;
        sine_table[60]=16'sd11942;
        sine_table[61]=16'sd11967;
        sine_table[62]=16'sd11986;
        sine_table[63]=16'sd11996;
        sine_table[64]=16'sd12000;
        sine_table[65]=16'sd11996;
        sine_table[66]=16'sd11986;
        sine_table[67]=16'sd11967;
        sine_table[68]=16'sd11942;
        sine_table[69]=16'sd11910;
        sine_table[70]=16'sd11870;
        sine_table[71]=16'sd11823;
        sine_table[72]=16'sd11769;
        sine_table[73]=16'sd11708;
        sine_table[74]=16'sd11640;
        sine_table[75]=16'sd11565;
        sine_table[76]=16'sd11483;
        sine_table[77]=16'sd11394;
        sine_table[78]=16'sd11299;
        sine_table[79]=16'sd11196;
        sine_table[80]=16'sd11087;
        sine_table[81]=16'sd10971;
        sine_table[82]=16'sd10848;
        sine_table[83]=16'sd10719;
        sine_table[84]=16'sd10583;
        sine_table[85]=16'sd10441;
        sine_table[86]=16'sd10293;
        sine_table[87]=16'sd10138;
        sine_table[88]=16'sd9978;
        sine_table[89]=16'sd9811;
        sine_table[90]=16'sd9638;
        sine_table[91]=16'sd9460;
        sine_table[92]=16'sd9276;
        sine_table[93]=16'sd9087;
        sine_table[94]=16'sd8891;
        sine_table[95]=16'sd8691;
        sine_table[96]=16'sd8485;
        sine_table[97]=16'sd8274;
        sine_table[98]=16'sd8059;
        sine_table[99]=16'sd7838;
        sine_table[100]=16'sd7613;
        sine_table[101]=16'sd7383;
        sine_table[102]=16'sd7148;
        sine_table[103]=16'sd6910;
        sine_table[104]=16'sd6667;
        sine_table[105]=16'sd6420;
        sine_table[106]=16'sd6169;
        sine_table[107]=16'sd5915;
        sine_table[108]=16'sd5657;
        sine_table[109]=16'sd5395;
        sine_table[110]=16'sd5131;
        sine_table[111]=16'sd4863;
        sine_table[112]=16'sd4592;
        sine_table[113]=16'sd4319;
        sine_table[114]=16'sd4043;
        sine_table[115]=16'sd3764;
        sine_table[116]=16'sd3483;
        sine_table[117]=16'sd3201;
        sine_table[118]=16'sd2916;
        sine_table[119]=16'sd2629;
        sine_table[120]=16'sd2341;
        sine_table[121]=16'sd2052;
        sine_table[122]=16'sd1761;
        sine_table[123]=16'sd1469;
        sine_table[124]=16'sd1176;
        sine_table[125]=16'sd883;
        sine_table[126]=16'sd589;
        sine_table[127]=16'sd294;
        sine_table[128]=16'sd0;
        sine_table[129]=-16'sd294;
        sine_table[130]=-16'sd589;
        sine_table[131]=-16'sd883;
        sine_table[132]=-16'sd1176;
        sine_table[133]=-16'sd1469;
        sine_table[134]=-16'sd1761;
        sine_table[135]=-16'sd2052;
        sine_table[136]=-16'sd2341;
        sine_table[137]=-16'sd2629;
        sine_table[138]=-16'sd2916;
        sine_table[139]=-16'sd3201;
        sine_table[140]=-16'sd3483;
        sine_table[141]=-16'sd3764;
        sine_table[142]=-16'sd4043;
        sine_table[143]=-16'sd4319;
        sine_table[144]=-16'sd4592;
        sine_table[145]=-16'sd4863;
        sine_table[146]=-16'sd5131;
        sine_table[147]=-16'sd5395;
        sine_table[148]=-16'sd5657;
        sine_table[149]=-16'sd5915;
        sine_table[150]=-16'sd6169;
        sine_table[151]=-16'sd6420;
        sine_table[152]=-16'sd6667;
        sine_table[153]=-16'sd6910;
        sine_table[154]=-16'sd7148;
        sine_table[155]=-16'sd7383;
        sine_table[156]=-16'sd7613;
        sine_table[157]=-16'sd7838;
        sine_table[158]=-16'sd8059;
        sine_table[159]=-16'sd8274;
        sine_table[160]=-16'sd8485;
        sine_table[161]=-16'sd8691;
        sine_table[162]=-16'sd8891;
        sine_table[163]=-16'sd9087;
        sine_table[164]=-16'sd9276;
        sine_table[165]=-16'sd9460;
        sine_table[166]=-16'sd9638;
        sine_table[167]=-16'sd9811;
        sine_table[168]=-16'sd9978;
        sine_table[169]=-16'sd10138;
        sine_table[170]=-16'sd10293;
        sine_table[171]=-16'sd10441;
        sine_table[172]=-16'sd10583;
        sine_table[173]=-16'sd10719;
        sine_table[174]=-16'sd10848;
        sine_table[175]=-16'sd10971;
        sine_table[176]=-16'sd11087;
        sine_table[177]=-16'sd11196;
        sine_table[178]=-16'sd11299;
        sine_table[179]=-16'sd11394;
        sine_table[180]=-16'sd11483;
        sine_table[181]=-16'sd11565;
        sine_table[182]=-16'sd11640;
        sine_table[183]=-16'sd11708;
        sine_table[184]=-16'sd11769;
        sine_table[185]=-16'sd11823;
        sine_table[186]=-16'sd11870;
        sine_table[187]=-16'sd11910;
        sine_table[188]=-16'sd11942;
        sine_table[189]=-16'sd11967;
        sine_table[190]=-16'sd11986;
        sine_table[191]=-16'sd11996;
        sine_table[192]=-16'sd12000;
        sine_table[193]=-16'sd11996;
        sine_table[194]=-16'sd11986;
        sine_table[195]=-16'sd11967;
        sine_table[196]=-16'sd11942;
        sine_table[197]=-16'sd11910;
        sine_table[198]=-16'sd11870;
        sine_table[199]=-16'sd11823;
        sine_table[200]=-16'sd11769;
        sine_table[201]=-16'sd11708;
        sine_table[202]=-16'sd11640;
        sine_table[203]=-16'sd11565;
        sine_table[204]=-16'sd11483;
        sine_table[205]=-16'sd11394;
        sine_table[206]=-16'sd11299;
        sine_table[207]=-16'sd11196;
        sine_table[208]=-16'sd11087;
        sine_table[209]=-16'sd10971;
        sine_table[210]=-16'sd10848;
        sine_table[211]=-16'sd10719;
        sine_table[212]=-16'sd10583;
        sine_table[213]=-16'sd10441;
        sine_table[214]=-16'sd10293;
        sine_table[215]=-16'sd10138;
        sine_table[216]=-16'sd9978;
        sine_table[217]=-16'sd9811;
        sine_table[218]=-16'sd9638;
        sine_table[219]=-16'sd9460;
        sine_table[220]=-16'sd9276;
        sine_table[221]=-16'sd9087;
        sine_table[222]=-16'sd8891;
        sine_table[223]=-16'sd8691;
        sine_table[224]=-16'sd8485;
        sine_table[225]=-16'sd8274;
        sine_table[226]=-16'sd8059;
        sine_table[227]=-16'sd7838;
        sine_table[228]=-16'sd7613;
        sine_table[229]=-16'sd7383;
        sine_table[230]=-16'sd7148;
        sine_table[231]=-16'sd6910;
        sine_table[232]=-16'sd6667;
        sine_table[233]=-16'sd6420;
        sine_table[234]=-16'sd6169;
        sine_table[235]=-16'sd5915;
        sine_table[236]=-16'sd5657;
        sine_table[237]=-16'sd5395;
        sine_table[238]=-16'sd5131;
        sine_table[239]=-16'sd4863;
        sine_table[240]=-16'sd4592;
        sine_table[241]=-16'sd4319;
        sine_table[242]=-16'sd4043;
        sine_table[243]=-16'sd3764;
        sine_table[244]=-16'sd3483;
        sine_table[245]=-16'sd3201;
        sine_table[246]=-16'sd2916;
        sine_table[247]=-16'sd2629;
        sine_table[248]=-16'sd2341;
        sine_table[249]=-16'sd2052;
        sine_table[250]=-16'sd1761;
        sine_table[251]=-16'sd1469;
        sine_table[252]=-16'sd1176;
        sine_table[253]=-16'sd883;
        sine_table[254]=-16'sd589;
        sine_table[255]=-16'sd294;
    end
    always @* begin
        case(note)
            7'd43:increment=tuning(32'd97999);
            7'd44:increment=tuning(32'd103826);
            7'd45:increment=tuning(32'd110000);
            7'd46:increment=tuning(32'd116541);
            7'd47:increment=tuning(32'd123471);
            7'd48:increment=tuning(32'd130813);
            7'd49:increment=tuning(32'd138591);
            7'd50:increment=tuning(32'd146832);
            7'd51:increment=tuning(32'd155563);
            7'd52:increment=tuning(32'd164814);
            7'd53:increment=tuning(32'd174614);
            7'd54:increment=tuning(32'd184997);
            7'd55:increment=tuning(32'd195998);
            7'd56:increment=tuning(32'd207652);
            7'd57:increment=tuning(32'd220000);
            7'd58:increment=tuning(32'd233082);
            7'd59:increment=tuning(32'd246942);
            7'd60:increment=tuning(32'd261626);
            7'd61:increment=tuning(32'd277183);
            7'd62:increment=tuning(32'd293665);
            7'd63:increment=tuning(32'd311127);
            7'd64:increment=tuning(32'd329628);
            7'd65:increment=tuning(32'd349228);
            7'd66:increment=tuning(32'd369994);
            7'd67:increment=tuning(32'd391995);
            7'd68:increment=tuning(32'd415305);
            7'd69:increment=tuning(32'd440000);
            7'd70:increment=tuning(32'd466164);
            7'd71:increment=tuning(32'd493883);
            7'd72:increment=tuning(32'd523251);
            7'd73:increment=tuning(32'd554365);
            7'd74:increment=tuning(32'd587330);
            7'd75:increment=tuning(32'd622254);
            7'd76:increment=tuning(32'd659255);
            7'd77:increment=tuning(32'd698456);
            7'd78:increment=tuning(32'd739989);
            7'd79:increment=tuning(32'd783991);
            7'd80:increment=tuning(32'd830609);
            7'd81:increment=tuning(32'd880000);
            7'd82:increment=tuning(32'd932328);
            7'd83:increment=tuning(32'd987767);
            7'd84:increment=tuning(32'd1046502);
            7'd85:increment=tuning(32'd1108731);
            default:increment=tuning(32'd195998); // G3
        endcase
    end
    wire [31:0] phase2=phase<<1,phase3=phase+(phase<<1),phase4=phase<<2;
    wire [31:0] phase5=phase+(phase<<2),phase6=(phase<<2)+(phase<<1);
    // Precompute the six interpolated harmonics between sample strobes.
    // Phase/amplitude are held for 1024 clocks in production. This pipeline
    // settles in six clocks, preserving the CA76 value at the next strobe.
    // Use sample_ce spacing >= 8 clocks (the standalone CA76 frame is 512).
    wire [31:0] harmonic_phase[0:5];
    assign harmonic_phase[0]=phase; assign harmonic_phase[1]=phase2;
    assign harmonic_phase[2]=phase3; assign harmonic_phase[3]=phase4;
    assign harmonic_phase[4]=phase5; assign harmonic_phase[5]=phase6;
    wire signed [15:0] harmonics[0:5];
    genvar harmonic;
    generate for(harmonic=0;harmonic<6;harmonic=harmonic+1) begin: interp
        reg [31:0] position_q;
        wire [7:0] next_address=position_q[31:24]+8'd1;
        reg signed [15:0] a_q,b_q,base_q,base_mul_q,result_q;
        reg [7:0] fraction_q,fraction_mul_q;
        reg signed [16:0] difference_q;
        reg signed [25:0] fraction_product_q;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                position_q<=0;a_q<=0;b_q<=0;base_q<=0;base_mul_q<=0;
                result_q<=0;fraction_q<=0;fraction_mul_q<=0;
                difference_q<=0;fraction_product_q<=0;
            end else begin
                position_q<=harmonic_phase[harmonic];
                a_q<=sine_table[position_q[31:24]];
                b_q<=sine_table[next_address];fraction_q<=position_q[23:16];
                difference_q<=$signed({b_q[15],b_q})-$signed({a_q[15],a_q});
                base_q<=a_q;fraction_mul_q<=fraction_q;
                fraction_product_q<=difference_q*$signed({1'b0,fraction_mul_q});
                base_mul_q<=base_q;
                result_q<=base_mul_q+(fraction_product_q>>>8);
            end
        end
        assign harmonics[harmonic]=result_q;
    end endgenerate
    wire signed [15:0] h1=harmonics[0],h2=harmonics[1],h3=harmonics[2];
    wire signed [15:0] h4=harmonics[3],h5=harmonics[4],h6=harmonics[5];
    wire signed [20:0] dry_mix=($signed(h1)>>>1)+($signed(h2)>>>6)+
        ($signed(h3)>>>7)+($signed(h4)>>>9)+($signed(h5)>>>10)+($signed(h6)>>>11);
    wire signed [20:0] bright_mix=($signed(h2)>>>5)+($signed(h2)>>>6)+
        ($signed(h3)>>>6)+($signed(h4)>>>8)+($signed(h5)>>>9);
    reg signed [20:0] dry_mix_q;
    reg signed [29:0] bright_product_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin dry_mix_q<=0;bright_product_q<=0;end
        else begin
            dry_mix_q<=dry_mix;
            bright_product_q<=bright_mix*$signed({1'b0,brightness});
        end
    end
    wire signed [30:0] complete_mix=$signed(dry_mix_q)+(bright_product_q>>>8);
    // One sample of mix latency keeps the wavetable/scaler timing separated.
    wire signed [37:0] product=body_mix*$signed({1'b0,amplitude});
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            phase<=0;amplitude<=0;pcm<=0;body_mix<=0;
        end else if(sample_ce) begin
            phase<=phase+increment;
            if(amplitude<target) begin
                if(target-amplitude<=ATTACK_STEP) amplitude<=target;
                else amplitude<=amplitude+ATTACK_STEP;
            end else if(amplitude>target) begin
                if(amplitude-target<=RELEASE_STEP) amplitude<=target;
                else amplitude<=amplitude-RELEASE_STEP;
            end
            if(pure_tone) body_mix<=$signed(h1)>>>1;
            else body_mix<=complete_mix[20:0];
            pcm<=product[30:15];
        end
    end
endmodule
