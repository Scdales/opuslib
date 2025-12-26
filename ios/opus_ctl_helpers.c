#include "opus_ctl_helpers.h"

int opus_encoder_ctl_set_bitrate(OpusEncoder *enc, opus_int32 bitrate) {
  return opus_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
}

int opus_encoder_ctl_set_dred_duration(OpusEncoder *enc, opus_int32 duration_ms) {
  return opus_encoder_ctl(enc, OPUS_SET_DRED_DURATION(duration_ms));
}

int opus_encoder_ctl_set_vbr(OpusEncoder *enc, opus_int32 vbr) {
  return opus_encoder_ctl(enc, OPUS_SET_VBR(vbr));
}

int opus_encoder_ctl_set_complexity(OpusEncoder *enc, opus_int32 complexity) {
  return opus_encoder_ctl(enc, OPUS_SET_COMPLEXITY(complexity));
}

int opus_encoder_ctl_set_inband_fec(OpusEncoder *enc, opus_int32 fec) {
  return opus_encoder_ctl(enc, OPUS_SET_INBAND_FEC(fec));
}

int opus_encoder_ctl_set_dtx(OpusEncoder *enc, opus_int32 dtx) {
  return opus_encoder_ctl(enc, OPUS_SET_DTX(dtx));
}
