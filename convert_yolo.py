from ultralytics import YOLO

# 1. Load the YOLOv8 Nano model
model = YOLO('yolov8n.pt') 

# 2. Convert and export model for mobile execution (Compatible with Ultralytics 8.4+)
output_path = model.export(format='tflite', imgsz=256)

print(f"SUCCESS! Mobile model created at: {output_path}")