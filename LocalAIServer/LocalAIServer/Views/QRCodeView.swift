//
//  QRCodeView.swift
//  LocalAIServer
//
//  QR Code generation for API endpoint sharing
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let endpoint: String
    
    @State private var qrCodeImage: UIImage?
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Scan to Connect")
                .font(.title2.bold())
            
            if let qrCodeImage = qrCodeImage {
                Image(uiImage: qrCodeImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 250, height: 250)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
            
            Text(endpoint)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            Button(action: saveQRCode) {
                Label("Save QR Code", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
        .navigationTitle("QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            
            guard let data = endpoint.data(using: .utf8) else { return }
            
            filter.message = data
            filter.correctionLevel = "M"
            
            if let outputImage = filter.outputImage,
               let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                
                DispatchQueue.main.async {
                    qrCodeImage = uiImage
                }
            }
        }
    }
    
    private func saveQRCode() {
        guard let qrCodeImage = qrCodeImage else { return }
        
        // Save to photo library
        UIImageWriteToSavedPhotosAlbum(qrCodeImage, nil, nil, nil)
    }
}

#Preview {
    NavigationView {
        QRCodeView(endpoint: "http://192.168.1.100:8080/v1")
    }
}
