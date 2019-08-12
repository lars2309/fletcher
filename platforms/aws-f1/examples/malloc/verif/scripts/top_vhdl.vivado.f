
# Utilities

${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilConv_pkg.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilInt_pkg.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilStr_pkg.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilMisc_pkg.vhd

${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilMem64_pkg.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilRam1R1W.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/util/UtilRam_pkg.vhd

# Fletcher packages

${FLETCHER_HARDWARE_DIR}/arrays/ArrayConfigParse_pkg.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayConfig_pkg.vhd
${FLETCHER_HARDWARE_DIR}/arrays/Array_pkg.vhd
${FLETCHER_HARDWARE_DIR}/arrow/Arrow_pkg.vhd
${FLETCHER_HARDWARE_DIR}/axi/Axi_pkg.vhd
${FLETCHER_HARDWARE_DIR}/buffers/Buffer_pkg.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/Interconnect_pkg.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/Stream_pkg.vhd
${FLETCHER_HARDWARE_DIR}/wrapper/Wrapper_pkg.vhd

# Fletcher files

${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamArb.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamBuffer.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamElementCounter.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamFIFOCounter.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamFIFO.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamGearbox.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamGearboxParallelizer.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamGearboxSerializer.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamNormalizer.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamPRNG.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamSlice.vhd
${FLETCHER_HARDWARE_DIR}/vhlib/stream/StreamSync.vhd

${FLETCHER_HARDWARE_DIR}/buffers/BufferReaderCmdGenBusReq.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferReaderCmd.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferReaderPost.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferReaderRespCtrl.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferReaderResp.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferReader.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferWriterCmdGenBusReq.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferWriterPreCmdGen.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferWriterPrePadder.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferWriterPre.vhd
${FLETCHER_HARDWARE_DIR}/buffers/BufferWriter.vhd

${FLETCHER_HARDWARE_DIR}/interconnect/BusReadArbiter.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusReadArbiterVec.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusReadBuffer.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusReadBenchmarker.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusWriteArbiter.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusWriteArbiterVec.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusWriteBenchmarker.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/BusWriteBuffer.vhd

${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderArb.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderLevel.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderListPrim.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderListSyncDecoder.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderListSync.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderList.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderNull.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderStruct.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReaderUnlockCombine.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayReader.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayWriterArb.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayWriterLevel.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayWriterListPrim.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayWriterListSync.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayWriter.vhd

${FLETCHER_HARDWARE_DIR}/axi/AxiMmio.vhd
${FLETCHER_HARDWARE_DIR}/axi/AxiReadConverter.vhd
${FLETCHER_HARDWARE_DIR}/axi/AxiWriteConverter.vhd

${FLETCHER_HARDWARE_DIR}/mm/MM_pkg.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMBarrier.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMDirector.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMFrames.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMGapFinder.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMGapFinderStep.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMHostInterface.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMRolodex.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMTranslator.vhd
${FLETCHER_HARDWARE_DIR}/mm/MMWalker.vhd

# Fletcher to AWS glue

$FLETCHER_EXAMPLES_DIR/malloc/hardware/ReactDelayCounter.vhd
$FLETCHER_EXAMPLES_DIR/malloc/hardware/fletcher_wrapper.vhd
$FLETCHER_EXAMPLES_DIR/malloc/hardware/axi_top.vhd
$FLETCHER_EXAMPLES_DIR/malloc/hardware/f1_top.vhd


