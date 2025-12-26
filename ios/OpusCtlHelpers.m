#import "OpusCtlHelpers.h"
#import "opus.h"

@implementation OpusCtlHelpers

+ (int)setBitrate:(void *)encoder bitrate:(int)bitrate {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_BITRATE(bitrate));
}

+ (int)setDredDuration:(void *)encoder durationMs:(int)durationMs {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_DRED_DURATION(durationMs));
}

+ (int)setVbr:(void *)encoder vbr:(int)vbr {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_VBR(vbr));
}

+ (int)setComplexity:(void *)encoder complexity:(int)complexity {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_COMPLEXITY(complexity));
}

+ (int)setInbandFec:(void *)encoder fec:(int)fec {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_INBAND_FEC(fec));
}

+ (int)setDtx:(void *)encoder dtx:(int)dtx {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_DTX(dtx));
}

@end
