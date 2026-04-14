FROM alpine:3.21 AS download

RUN apk add --no-cache curl

ARG MODEL_VERSION=v1.0
RUN curl -fSL -o /tmp/yolov9-s-relu6-best_320_int8_edgetpu.tflite \
      "https://github.com/dbro/frigate-detector-edgetpu-yolo9/releases/download/${MODEL_VERSION}/yolov9-s-relu6-best_320_int8_edgetpu.tflite" && \
    curl -fSL -o /tmp/labels-coco17.txt \
      "https://raw.githubusercontent.com/dbro/frigate-detector-edgetpu-yolo9/refs/heads/main/labels-coco17.txt"

FROM busybox:1.37
COPY --from=download /tmp/yolov9-s-relu6-best_320_int8_edgetpu.tflite /models/yolov9-s-relu6-best_320_int8_edgetpu.tflite
COPY --from=download /tmp/labels-coco17.txt /models/labels-coco17.txt
