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
    @State private var idealBaseTimes: [Int16: Date] = [:]
    @State private var showingBaseTimePicker = false
    @State private var baseTime: Date? = nil

        // Default if no base time saved: current hour, 0 minutes
        private var defaultBaseTime: Date {
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        }

        // The effective base time for participant 0
        private var effectiveBaseTime: Date {
            baseTime ?? defaultBaseTime
        }

    var body: some View {
        NavigationView {
            VStack {
                // Header with current checkpoint and selection button
                HStack {
                    Text("VTC: \(selectedCheckpoint)")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingCheckpointSelection = true }) {
                        Label("Kies VTC", systemImage: "flag")
                    }
                }
                .padding()

                // List of participants 1–100 for the selected checkpoint
                //CheckpointListView(checkpoint: selectedCheckpoint)
                // List of participants 1–100 for the selected checkpoint
                CheckpointListView(
                    checkpoint: selectedCheckpoint,
                    idealBase: idealBaseTimes[selectedCheckpoint] ?? defaultBaseTime,
                    isFinish: selectedCheckpoint == 20
                )
            }
            .navigationTitle("Equipes")
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
            .sheet(isPresented: $showingBaseTimePicker) {
                BaseTimePicker(
                    baseTime: idealBaseTimes[selectedCheckpoint] ?? defaultBaseTime,
                    onSave: { newBase in
                        idealBaseTimes[selectedCheckpoint] = newBase
                        showingBaseTimePicker = false
                    },
                    onCancel: { showingBaseTimePicker = false }
                )
            }
        }
    }
    
    // Load base time (participant 0) from Core Data
    private func loadBaseTime() {
        let request: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        request.predicate = NSPredicate(format: "participant_id == 0 AND checkpoint_id == %d", selectedCheckpoint)
        request.fetchLimit = 1
        do {
            if let entry = try viewContext.fetch(request).first, let ts = entry.timestamp {
                baseTime = ts
            } else {
                baseTime = nil
            }
        } catch {
            print("Failed to load base time: \(error)")
            baseTime = nil
        }
    }

    // Save base time as participant 0 entry in Core Data
    private func saveBaseTime(_ date: Date) {
        let request: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        request.predicate = NSPredicate(format: "participant_id == 0 AND checkpoint_id == %d", selectedCheckpoint)
        request.fetchLimit = 1
        do {
            let entry = try viewContext.fetch(request).first ?? ParticipantTime(context: viewContext)
            entry.participant_id = 0
            entry.checkpoint_id = selectedCheckpoint
            entry.timestamp = date
            try viewContext.save()
        } catch {
            print("Failed to save base time: \(error)")
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
           var csv = "VTC,EQ,date,time\n"
           for pid in 1...100 {
               let key = Int16(pid)
               let dateString = timestampsByParticipant[key].map { dateFormatter.string(from: $0) } ?? ""
               let timeString = timestampsByParticipant[key].map { timeFormatter.string(from: $0) } ?? ""
               csv += "\(selectedCheckpoint),\(pid),\(dateString),\(timeString)\n"
           }
           let filename = "vtc-\(selectedCheckpoint)-participants.csv"
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
                checkpoint: selectedCheckpoint,
                idealBase: idealBaseTimes[selectedCheckpoint] ?? Date(),
                isFinish: selectedCheckpoint == 20
            )
            .environment(\.managedObjectContext, viewContext)

            let hostingVC = UIHostingController(rootView: checkInView)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                root.present(hostingVC, animated: true)
            }
        }
    
}

// Picker for base time (participant 0)
struct BaseTimePicker: View {
    @State var baseTime: Date
    var onSave: (Date) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                DatePicker("Base time (Participant 0)", selection: $baseTime, displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("Set Base Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(baseTime) }
                }
            }
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
    let idealBase: Date
    let isFinish: Bool

    @FetchRequest private var times: FetchedResults<ParticipantTime>

    init(checkpoint: Int16, idealBase: Date, isFinish: Bool) {
        self.checkpoint = checkpoint
        self.idealBase = idealBase
        self.isFinish = isFinish
        _times = FetchRequest(
            entity: ParticipantTime.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \ParticipantTime.participant_id, ascending: true)],
            predicate: NSPredicate(format: "checkpoint_id == %d", checkpoint)
        )
    }

    var body: some View {
        List(0...100, id: \.self) { pid in
            let match = times.first { $0.participant_id == pid }
            HStack {
                Text(pid == 0 ? "Base" : "EQ: \(pid)")
                Spacer()
                if let entry = match, let time = entry.timestamp {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(time, formatter: itemFormatter)
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showCheckIn(for: pid) }
        }
    }

    private func showCheckIn(for participantID: Int) {
        let checkInView = CheckInView(
            participantID: Int16(participantID),
            checkpoint: checkpoint,
            idealBase: idealBase,
            isFinish: isFinish
        )
        .environment(\.managedObjectContext, viewContext)

        let hostingVC = UIHostingController(rootView: checkInView)
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
                        Text("VTC \(cp)")
                        if cp == selectedCheckpoint {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Kies VTC")
        }
    }
}

struct CheckInView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode

    let participantID: Int16
    let checkpoint: Int16
    let idealBase: Date       // fallback base if no saved record
    let isFinish: Bool

    @State private var currentBaseTime: Date = Date()
    @State private var checkInTime: Date = Date()
    
    private var minTime: Date {
        Date().addingTimeInterval(-120)
    }
    private var maxTime: Date {
        .distantFuture
    }
    
    private var dateRange: ClosedRange<Date> {
        if participantID == 0 {
            // no restrictions
            return Date.distantPast...Date.distantFuture
        } else {
            return minTime...maxTime
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Popping Allowed Window
                VStack(alignment: .leading, spacing: 16) {
                    Text("Allowed Window")
                        .font(.title3).bold()
                        .padding(.horizontal, 8)

                    // Ideal
                    Label {
                        HStack(alignment: .center, spacing: 4) {
                            Text("Ideal:")
                                .font(.subheadline).bold()
                            Spacer()
                            Text(timeFormatted(idealTime()))
                                .font(.body)
                        }
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground)))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                    // Earliest
                    Label {
                        HStack(alignment: .center, spacing: 4) {
                            Text("Earliest:")
                                .font(.subheadline).bold()
                            Spacer()
                            Text(timeFormatted(minTime))
                                .font(.body)
                        }
                    } icon: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground)))
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)

                    // Latest
                    Label {
                        HStack(alignment: .center, spacing: 4) {
                            Text("Latest:")
                                .font(.subheadline).bold()
                            Spacer()
                            Text(timeFormatted(maxTime))
                                .font(.body)
                        }
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground)))
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                }
                .padding(.vertical)
                Section(header: Text("Kies WPT")) {
                    DatePicker(
                        "Time",
                        selection: $checkInTime,
                        in: dateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle(participantID == 0
                             ? "Set Base Time"
                             : "Check-in EQ \(participantID)")
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
        .onAppear {
            loadBaseTime2()
        }
    }

    private func loadBaseTime() {
        let req: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        req.predicate = NSPredicate(format: "participant_id == 0 AND checkpoint_id == %d", checkpoint)
        req.fetchLimit = 1
        do {
            if let entry = try viewContext.fetch(req).first,
               let ts = entry.timestamp {
                currentBaseTime = ts
            } else {
                currentBaseTime = idealBase
            }
        } catch {
            currentBaseTime = idealBase
        }
        checkInTime = idealTime()
    }
    
    private func loadBaseTime2() {
        // 1) First: figure out your base time (the “0th” entry) exactly as before
        let baseReq: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        baseReq.predicate = NSPredicate(
          format: "participant_id == 0 AND checkpoint_id == %d",
          checkpoint
        )
        baseReq.fetchLimit = 1

        do {
            if let entry = try viewContext.fetch(baseReq).first,
               let ts = entry.timestamp {
                currentBaseTime = ts
            } else {
                currentBaseTime = idealBase
            }
        } catch {
            currentBaseTime = idealBase
        }

        // 2) Now try to load the *last saved* check-in for this participant
        let savedReq: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        savedReq.predicate = NSPredicate(
          format: "participant_id == %d AND checkpoint_id == %d",
          participantID, checkpoint
        )
        savedReq.fetchLimit = 1

        do {
            if let saved = try viewContext.fetch(savedReq).first,
               let savedTs = saved.timestamp {
                // if we have a saved timestamp, show that
                checkInTime = savedTs
            } else {
                // otherwise fall back to your idealTime()
                checkInTime = idealTime()
            }
        } catch {
            checkInTime = idealTime()
        }
    }

    private func idealTime() -> Date {
        Calendar.current.date(
           byAdding: .minute,
           value: Int(participantID),
           to: currentBaseTime
        ) ?? currentBaseTime
    }

    private func timeFormatted(_ date: Date) -> String {
        let df = DateFormatter()
        //df.dateFormat = "dd-MM-yyyy HH:mm"
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func saveEntry() {
        let req: NSFetchRequest<ParticipantTime> = ParticipantTime.fetchRequest()
        req.predicate = NSPredicate(
            format: "participant_id == %d AND checkpoint_id == %d",
            participantID, checkpoint
        )
        req.fetchLimit = 1
        do {
            let entry = try viewContext.fetch(req).first
                        ?? ParticipantTime(context: viewContext)
            entry.participant_id = participantID
            entry.checkpoint_id = checkpoint
            entry.timestamp = checkInTime
            try viewContext.save()
        } catch {
            print("Failed to save check-in:", error)
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
