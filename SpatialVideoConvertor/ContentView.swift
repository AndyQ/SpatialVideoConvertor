//
//  ContentView.swift
//  SpatialVideoConvertor
//
//  Created by Andy Qua on 04/01/2024.
//

import SwiftUI
import PhotosUI
import AVKit

struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "movie.mp4")
            
            if FileManager.default.fileExists(atPath: copy.path()) {
                try FileManager.default.removeItem(at: copy)
            }
            
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}

struct Progress : View {
    @Binding var progress : Float
    
    var body: some View {
        ProgressView(value:progress)
    }
}


struct ContentView: View {
    enum LoadState {
        case unknown, loading, loaded(Movie), failed
    }
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var loadState = LoadState.unknown
    @State private var  url: URL?
    @State private var progress: Float = 0

    @State private var error: DisplayError? = nil

    var body: some View {
        VStack {
            PhotosPicker("Select movie", selection: $selectedItem, matching: .videos)
            switch loadState {
                case .unknown:
                    EmptyView()
                case .loading:
                    ProgressView()
                case .loaded(let movie):
                    VideoPlayer(player: AVPlayer(url: movie.url))
                case .failed:
                    Text("Import failed")
            }
            
            Button( "Convert" ) {
                progress = 0
                convertVideo()
            }
            
            Progress(progress:$progress)
        }
        .padding()
        .onChange(of: selectedItem) { _, _ in
            Task {
                do {
                    loadState = .loading
                    progress = 0

                    if let movie = try await selectedItem?.loadTransferable(type: Movie.self) {
                        url = movie.url

                        loadState = .loaded(movie)
                    } else {
                        loadState = .failed
                    }
                } catch {
                    loadState = .failed
                }
            }
        }
        .errorAlert($error)

    }
}

extension ContentView {
    func convertVideo() {
        guard let url else { return }
        let inputFile = url

        let outputFile = URL.documentsDirectory.appending(path:"output.mp4")
        try? FileManager.default.removeItem(at: outputFile )
        print( outputFile )
        
        print( "outputFile - \(outputFile)")

        Task {
            print( "Converting video...")
            let convertor = VideoConvertor()
            
            do {
                try await convertor.convertVideo(inputFile: inputFile, outputFile: outputFile ) { progress in
                    
                    self.progress = progress
                }
            } catch {
                print( "error - \(error)")
                self.error = DisplayError( title: "Error converting", message: "\(error)")

                
                return
            }
            print( "Finished")
            
            let movie = Movie(url: outputFile)
            loadState = .loaded(movie)

        }
    }
}

#Preview {
    ContentView()
}
