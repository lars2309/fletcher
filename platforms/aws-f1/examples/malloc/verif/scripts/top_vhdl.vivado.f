# Fletcher files

${FLETCHER_HARDWARE_DIR}/utils/Utils.vhd
${FLETCHER_HARDWARE_DIR}/utils/SimUtils.vhd
${FLETCHER_HARDWARE_DIR}/utils/Ram1R1W.vhd

${FLETCHER_HARDWARE_DIR}/buffers/Buffers.vhd
${FLETCHER_HARDWARE_DIR}/interconnect/Interconnect.vhd

${FLETCHER_HARDWARE_DIR}/streams/Streams.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamArb.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamBuffer.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamFIFOCounter.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamFIFO.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamGearbox.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamNormalizer.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamParallelizer.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamSerializer.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamSlice.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamSync.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamElementCounter.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamPseudoRandomGenerator.vhd
${FLETCHER_HARDWARE_DIR}/streams/StreamAccumulator.vhd

${FLETCHER_HARDWARE_DIR}/arrays/ArrayConfigParse.vhd
${FLETCHER_HARDWARE_DIR}/arrays/ArrayConfig.vhd
${FLETCHER_HARDWARE_DIR}/arrays/Arrays.vhd

${FLETCHER_HARDWARE_DIR}/arrow/Arrow.vhd

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

${FLETCHER_HARDWARE_DIR}/wrapper/Wrapper.vhd
${FLETCHER_HARDWARE_DIR}/wrapper/UserCoreController.vhd

${FLETCHER_HARDWARE_DIR}/axi/axi.vhd
${FLETCHER_HARDWARE_DIR}/axi/axi_mmio.vhd
${FLETCHER_HARDWARE_DIR}/axi/axi_read_converter.vhd
${FLETCHER_HARDWARE_DIR}/axi/axi_write_converter.vhd

${FLETCHER_HARDWARE_DIR}/mm/MM.vhd
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

$FLETCHER_EXAMPLES_DIR/malloc/hardware/fletcher_wrapper.vhd
$FLETCHER_EXAMPLES_DIR/malloc/hardware/axi_top.vhd
$FLETCHER_EXAMPLES_DIR/malloc/hardware/f1_top.vhd


