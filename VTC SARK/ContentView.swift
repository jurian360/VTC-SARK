//
//  ContentView.swift
//  VTC SARK
//
//  Created by Raoul Brahim on 23-05-2025.
//

import SwiftUI
import CoreData
import AVFoundation

// Main view showing participants for the selected checkpoint
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedCheckpoint: Int16 = 1
    @State private var showingCheckpointSelection = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showingQRScanner = false
    @State private var scannedParticipant: Int16? = nil

    var body: some View {
        NavigationView {
            VStack {
                // Header with current checkpoint and selection button
                HStack {
                    Text("Checkpoint \(selectedCheckpoint)")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingCheckpointSelection = true }) {
                        Label("Select Checkpoint", systemImage: "flag")
                    }
                }
                .padding()

                // List of participants 1–100 for the selected checkpoint
                CheckpointListView(checkpoint: selectedCheckpoint)
            }
            .navigationTitle("Participants")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                                    Button(action: exportCSV) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    Button(action: { showingQRScanner = true }) {
                                        Image(systemName: "qrcode.viewfinder")
                                    }
                                }
                        }
            .sheet(isPresented: $showingCheckpointSelection) {
                CheckpointSelectionView(selectedCheckpoint: $selectedCheckpoint)
            }
            .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
                if let url = shareURL {
                    ActivityView(activityItems: [url])
                }
            }
            .sheet(isPresented: $showingQRScanner, onDismiss: handleScannedParticipant) {
                QRCodeScannerView { scannedValue in
                    if let pid = Int16(scannedValue) {
                        scannedParticipant = pid
                    }
                    showingQRScanner = false
                }
            }
        }
    }
    
    // Called when the QR scanner sheet dismisses
    private func handleScannedParticipant() {
        if let pid = scannedParticipant {
            presentCheckIn(for: pid)
            scannedParticipant = nil
        }
    }
    
    // Export CSV for sharing
   private func exportCSV() {
       let request: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
       request.predicate = NSPredicate(format: "checkpoint_id == %d", selectedCheckpoint)
       do {
           let entries = try viewContext.fetch(request)
           // Collect only non-nil timestamps
           var timestampsByParticipant: [Int16: Date] = [:]
           for entry in entries {
               if let ts = entry.timestamp {
                   timestampsByParticipant[entry.participant_id] = ts
               }
           }
           let dateFormatter = DateFormatter()
           dateFormatter.dateFormat = "dd-MM-yyyy"
           let timeFormatter = DateFormatter()
           timeFormatter.dateFormat = "HH:mm"
           var csv = "checkpoint_id,participant_id,date,time\n"
           for pid in 1...100 {
               let key = Int16(pid)
               let dateString = timestampsByParticipant[key].map { dateFormatter.string(from: $0) } ?? ""
               let timeString = timestampsByParticipant[key].map { timeFormatter.string(from: $0) } ?? ""
               csv += "\(selectedCheckpoint),\(pid),\(dateString),\(timeString)\n"
           }
           let filename = "checkpoint-\(selectedCheckpoint)-participants.csv"
           let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
           try csv.write(to: url, atomically: true, encoding: .utf8)
           shareURL = url
           showShareSheet = true
       } catch {
           print("Error exporting CSV: \(error)")
       }
   }
    
    // Present the CheckInView for a given participant
    private func presentCheckIn(for participantID: Int16) {
        let checkInView = CheckInView(
            participantID: participantID,
            checkpoint: selectedCheckpoint
        )
        .environment(\.managedObjectContext, viewContext)

        let hostingVC = UIHostingController(rootView: checkInView)
//        UIApplication.shared.windows.first?.rootViewController?
//            .present(hostingVC, animated: true)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    root.present(hostingVC, animated: true)
                }
    }
    
}

// Sheet for iOS share
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// View listing participants and their check-in times
struct CheckpointListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let checkpoint: Int16

    @FetchRequest private var times: FetchedResults<ParticipantTime>

    init(checkpoint: Int16) {
        self.checkpoint = checkpoint
        _times = FetchRequest(
            entity: ParticipantTime.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \ParticipantTime.participant_id, ascending: true)],
            predicate: NSPredicate(format: "checkpoint_id == %d", checkpoint)
        )
    }

    var body: some View {
        List(1...100, id: \.self) { pid in
            let match = times.first { $0.participant_id == pid }
            HStack {
                Text("#\(pid)")
                Spacer()
                if let entry = match, let time = entry.timestamp {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(time, formatter: itemFormatter)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showCheckIn(for: pid) }
        }
    }

    private func showCheckIn(for participantID: Int) {
        let checkInView = CheckInView(
            participantID: Int16(participantID),
            checkpoint: checkpoint
        )
        .environment(\.managedObjectContext, viewContext)

        let hostingVC = UIHostingController(rootView: checkInView)
//        UIApplication.shared.windows.first?.rootViewController?
//            .present(hostingVC, animated: true)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    root.present(hostingVC, animated: true)
                }
    }
}

// View to select a checkpoint (1–20)
struct CheckpointSelectionView: View {
    @Binding var selectedCheckpoint: Int16
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List(1...20, id: \.self) { cp in
                Button(action: {
                    selectedCheckpoint = Int16(cp)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Text("Checkpoint \(cp)")
                        if cp == selectedCheckpoint {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Select Checkpoint")
        }
    }
}

// View to check in a participant with a date picker
struct CheckInView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    let participantID: Int16
    let checkpoint: Int16
    @State private var checkInTime: Date = Date()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Select Check-in Time")) {
                    DatePicker(
                        "Time",
                        selection: $checkInTime,
                        in: Calendar.current.date(byAdding: .minute, value: -2, to: Date())!...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("Check-in #\(participantID)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func saveEntry() {
        let request: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        request.predicate = NSPredicate(
            format: "participant_id == %d AND checkpoint_id == %d",
            participantID, checkpoint
        )
        do {
            let results = try viewContext.fetch(request)
            let entry = results.first ?? ParticipantTime(context: viewContext)
            entry.participant_id = participantID
            entry.checkpoint_id = checkpoint
            entry.timestamp = checkInTime
            try viewContext.save()
        } catch {
            print("Failed to save check-in: \(error)")
        }
    }
}

// QR Code Scanner
struct QRCodeScannerView: UIViewControllerRepresentable {
    var completion: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let session = AVCaptureSession()
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            return controller
        }
        session.addInput(videoInput)
        let metadataOutput = AVCaptureMetadataOutput()
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = UIScreen.main.bounds
        previewLayer.videoGravity = .resizeAspectFill
        controller.view.layer.addSublayer(previewLayer)
        // Start running on a background thread to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var completion: (String) -> Void

        init(completion: @escaping (String) -> Void) {
            self.completion = completion
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let stringValue = object.stringValue else {
                return
            }
            completion(stringValue)
        }
    }
}

// Shared date formatter
private var itemFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
