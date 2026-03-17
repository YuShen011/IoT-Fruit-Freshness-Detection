!pip install ultralytics

from ultralytics import YOLO
# Load a model
model = YOLO("yolo11n.pt")

!pip install roboflow
from roboflow import Roboflow
rf = Roboflow(api_key="YOUR_ROBOFLOW_API_KEY")
project = rf.workspace("cselabfu").project("apple-n5nza-bmkm9-q1qll")
version = project.version(1)
dataset = version.download("yolov11")

# Train the model
train_results = model.train(
    data="/content/apple-1/data.yaml", # path to dataset YAML
    epochs=100, # number of training epochs
    imgsz=640, # training image size
    device="0", # device to run on, i.e. device=0 or device=0,1,2,3 or device=cpu
)