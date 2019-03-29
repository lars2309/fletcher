for (int i=0; i<(num_buf_bytes+3)/4; i++) begin
  tb.hm_put_byte(.addr(i+0), .d(i[(i%4) +: 8]));
  tb.hm_put_byte(.addr(i+1), .d(i[(i%4) +: 8]));
  tb.hm_put_byte(.addr(i+2), .d(i[(i%4) +: 8]));
  tb.hm_put_byte(.addr(i+3), .d(i[(i%4) +: 8]));
end

