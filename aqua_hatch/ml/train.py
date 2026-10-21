"""Train a baseline on a user-labelled larva dataset; no trained weights bundled."""
import argparse
from ultralytics import YOLO
p=argparse.ArgumentParser()
p.add_argument('--data',required=True,help='dataset.yaml with class 0: larva')
p.add_argument('--epochs',type=int,default=100)
p.add_argument('--imgsz',type=int,default=960)
p.add_argument('--device',default='cpu')
a=p.parse_args()
model=YOLO('yolov8n.pt')
model.train(data=a.data,epochs=a.epochs,imgsz=a.imgsz,device=a.device,project='runs/larvae',name='baseline')
