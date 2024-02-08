//
//  ContentView.swift
//  ProtectivePath
//
//  Created by Messs  on 5/2/24.
//

import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        NavigationView {
            ZStack {
                storyboardview().edgesIgnoringSafeArea(.all)
                VStack {
                    HStack {
                        NavigationLink(destination: DndView()){
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 50, height: 50) // Adjust the width and height of the circle
                                
                                Image(systemName: "camera.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundColor(.blue)
                                    .frame(width: 25, height: 25) // Adjust the width and height of the image
                            }
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                        .padding(.top,120) // Adjust top padding here if needed
                        .padding(.leading, -10) // Adjust left padding here
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider{
    static var previews: some View{
        ContentView()
    }
}

struct storyboardview: UIViewControllerRepresentable{
    func makeUIViewController(context content : Context) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let controller = storyboard.instantiateViewController(identifier: "Home")
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
