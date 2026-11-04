// B D203 UI; current D202 interconnect scene preserved.
localparam integer UI_RAW_BYTES=469184,UI_PACKED_BYTES=160943;
localparam integer UI_STREAM_AW=18,UI_TILE_COUNT=9906;
localparam integer UI_SCENE_COUNT=16,UI_SEGMENT_COUNT=1866;
localparam [31:0] UI_RAW_CRC=32'hf1e51e1f;
localparam [28:0] UI_DDR_BASE_WORD=29'h0800000;
localparam [28:0] UI_SEGMENTS_BASE_WORD=29'h0802000;
localparam [28:0] UI_TILES_BASE_WORD=29'h08094a0;
