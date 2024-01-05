//
//  ErrorHandling.swift
//  SFXR
//
//  Created by Andy Qua on 02/01/2024.
//

import SwiftUI

struct DisplayError: LocalizedError {
    
    var errorDescription: String?
    var errorMessage: String?

    init( title: String, message: String ) {
        self.errorDescription = title
        self.errorMessage = message
    }
}

struct ErrorAlert: ViewModifier {
    
    @Binding var error: DisplayError?
    var isShowingError: Binding<Bool> {
        Binding {
            error != nil
        } set: { _ in
            error = nil
        }
    }
    
    func body(content: Content) -> some View {
        content
            .alert(isPresented: isShowingError, error: error) { _ in
            } message: { error in
                if let message = error.errorMessage {
                    Text(message)
                }
            }
    }
}

extension View {
    func errorAlert(_ error: Binding<DisplayError?>) -> some View {
        self.modifier(ErrorAlert(error: error))
    }
}
