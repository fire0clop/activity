import CoreLocation
import MapKit
import SwiftUI

/// Выбор точки встречи на карте: пользователь двигает карту, пин зафиксирован по центру.
struct MapPickerView: View {
    var onPick: (CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationManager()

    private let moscow = CLLocationCoordinate2D(latitude: 55.751, longitude: 37.618)
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var centeredOnUser = false

    init(onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onPick = onPick
        let start = CLLocationCoordinate2D(latitude: 55.751, longitude: 37.618)
        _center = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) { UserAnnotation() }
                    .onMapCameraChange(frequency: .continuous) { ctx in center = ctx.region.center }
                    .mapControls { MapUserLocationButton() }
                    .ignoresSafeArea(edges: .bottom)

                // Фиксированный маркер по центру экрана = центр карты.
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                    .shadow(radius: 3)
            }
            .overlay(alignment: .bottom) {
                Button {
                    onPick(center)
                    dismiss()
                } label: {
                    Text("Выбрать эту точку")
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            .navigationTitle("Точка встречи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
            }
            .onAppear { location.request() }
            .onReceive(location.$coordinate.compactMap { $0 }) { c in
                guard !centeredOnUser else { return }
                centeredOnUser = true
                center = c
                position = .region(MKCoordinateRegion(
                    center: c, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            }
        }
    }
}
