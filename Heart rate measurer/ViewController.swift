//
//  ViewController.swift
//  Heart rate measurer
//
//  Created by Ghiffari on 04/07/2018.
//  Copyright © 2018 Ghifax Games. All rights reserved.
//

var videoPreviewLayer: AVCaptureVideoPreviewLayer?
var count = 0

// Libraries
import UIKit
import Charts
import AVFoundation
// Gloval variables
var captureSession: AVCaptureSession?
var frames = [Double]()
class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate {
    
    
    @IBOutlet var countdown: UILabel!
    var flag = 0
    @IBOutlet var previewView: UIImageView!
    @IBOutlet var bpmLabel: UILabel!
    @IBAction func captureBut(_ sender: Any) {
        lineChart.data?.clearValues()
        frames.removeAll()
        if flag == 0 {
            //Declare instrument to capture frames
            guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {return} // Checks if device can record video
            
            do {
                if captureDevice.hasTorch { // Check if it has a torch
                    do{
                        try captureDevice.lockForConfiguration()
                        
                        captureDevice.torchMode = .on
                        captureDevice.unlockForConfiguration()
                        captureDevice.activeVideoMinFrameDuration = CMTimeMake(1, 30) // Make sure fps is constant 30fps
                        captureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, 30)
                    } catch {
                        print("Torch error")
                    }
                    
                } else {
                    print("No torch here")
                }
            
                let input = try AVCaptureDeviceInput(device: captureDevice) // Tries to create the input for the session
                
                captureSession = AVCaptureSession() // Creates the session and add the input
                captureSession?.beginConfiguration()
                captureSession?.addInput(input)
                
                let output = AVCaptureVideoDataOutput() // Initialising the output from the session
                videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!) // Setting the
                videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
                videoPreviewLayer?.frame = CGRect(x: 10, y: 10, width: 100, height: 100)
                
                output.videoSettings =  [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String : Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
                
                let capture_queue = DispatchQueue(label: "captureQueue", attributes: []) //Creating a queue to store the frames in
                output.setSampleBufferDelegate(self, queue: capture_queue)
                output.alwaysDiscardsLateVideoFrames = false
                captureSession?.addOutput(output)
                guard let connection = output.connection(with: AVMediaType.video) else {print("fail"); return }
                guard connection.isVideoOrientationSupported else { return }
                connection.videoOrientation = .portrait
                captureSession?.commitConfiguration()
                captureSession?.startRunning()
                count = 15
                self.countdown.text = String(count)
                flag = 1
                print("Start")
            } catch {
                print("error")
            }
        }else { flag = 0; captureSession?.stopRunning();print("Stop")}
    }
    
    // Function that occurs whenever an output is received
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if frames.count < 450 {
            guard let CIOutput = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer) else {return}
            
            DispatchQueue.main.async {
                if frames.count < 450{ // Only 15 seconds of frames will be processed
                
                    // Get average colour from each framge
                    let avgColourPix = CIFilter(name: "CIAreaAverage")
                    avgColourPix?.setValue(CIOutput, forKey: kCIInputImageKey)
                    let ciimage = avgColourPix?.outputImage // Obtain output image from filter
                    let cgImage = CIContext().createCGImage(ciimage!, from: (ciimage?.extent)!) // convert CIImage into CGImage
                    let (red, green, blue) = cgImage!.colors() // Obtains RGB value
                    let Hue = RGBtoHue(red, green, blue) // Converts RGB into Hue
                    let num = Double(Hue)
                    frames.append(num)
                    
                    count = Int(round(14.0 - Double(frames.count / 30)))
                    if count == 0 {
                        self.countdown.text = "Done"
                    }else if count > 0{
                        self.countdown.text = String(count)
                    }
                    if frames.count > 151 {
                        
                        let filteredFrames = butterworthFilter(inputData: frames) // Adds butterworth filter onto frame
                        let stabilisedFrames = subArray(filteredFrames, 150, filteredFrames.count-1) // Removes the first 150 frames due to stabilisation
                        self.updateGraphdata(stabilisedFrames, self.lineChart) // Plot data onto graph
                        
                    }
                    
                    
                    // Procession the hue values
                    if frames.count == 450{
                        //print("looping")
                        let filteredFrames = butterworthFilter(inputData: frames) // Adds butterworth filter onto frame
                        let stabilisedFrames = subArray(filteredFrames, 150, filteredFrames.count-1) // Removes the first 150 frames due to stabilisation
                        let signals = detectPeak(dataPoint: stabilisedFrames, lag: 7, influence: 0.1, threshold: 2) // Finds peak from data
                        let (bpm1,bpm2,bpm3) = BpmAlgo(signals,stabilisedFrames)
                        let text = """
                        BPM is \(Int(round(bpm2))) algo 2
                        """
                        self.bpmLabel.text = text // Outputs the 3 bpms calculated.
                        
                    }
                    
                }
            }
            
        } else {
            
            captureSession?.stopRunning()
            
        }
        
        
    }
    
    //Function to convert frames from output into CIImage
    func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> CIImage? {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {return nil} //Get frame from queue
        let ciImage = CIImage(cvPixelBuffer: imageBuffer) // Convert into CIImage
        return ciImage
        
    }
    
    
    
    @IBOutlet var lineChart: LineChartView!
        
    // Procedure to create a graph from a given data set
    func updateGraphdata(_ newY:[Double],_ graph: LineChartView){ // Takes in the data set and a graph
        
        //Variable to hold data set
        var lineChartEntry = [ChartDataEntry]()
        
        for i in 0...newY.count-1{
            let value = ChartDataEntry(x: Double(lineChartEntry.count), y: newY[i])
            lineChartEntry.append(value)
            
            
        }
        let line1 = LineChartDataSet(values: lineChartEntry, label: "numbers")
        
        line1.circleRadius = 1
        line1.circleHoleRadius = 0
        line1.colors = [NSUIColor.red]
        line1.label = "Bloodflow"
        line1.valueTextColor = NSUIColor.white
        
        let data = LineChartData()
        data.addDataSet(line1)
        graph.data = data
        
        
    }
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        lineChart.xAxis.labelPosition = XAxis.LabelPosition.bottom
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
}

