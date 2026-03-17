import pathlib
temp = pathlib.PosixPath
pathlib.PosixPath = pathlib.WindowsPath

from ultralytics import YOLO

model = YOLO(r"C:\...\yolov11\best.pt") # Load your YOLOv11 model
results = model.predict(r"C:\...\photo\mix2.jpg") # Replace with your image path
print(results)

# Perform inference
results = model(r"C:\...\photo\mix2.jpg")

# Iterate through each detection in the results
for result in results: # 'results' is a list
    boxes = result.boxes # Access detected bounding boxes
    names = result.names # Map class IDs to class names

    for box in boxes: # Iterate over each box
        class_id = int(box.cls) # Class ID
        class_name = names[class_id] # Get class name
        confidence = box.conf.item() # Convert tensor to float
        print(f"Detected class: {class_name}, Confidence: {confidence:.2f}")