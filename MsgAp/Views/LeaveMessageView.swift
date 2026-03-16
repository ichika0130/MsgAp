import SwiftUI
import CoreLocation

struct LeaveMessageView: View {
    let coordinate: CLLocationCoordinate2D
    let store: MessageStore

    @Environment(\.dismiss) private var dismiss

    // Index-based state avoids Hashable/Equatable conformance on the data types.
    // All three start at 0, so composedMessage is always non-nil.
    @State private var templateIdx: Int = 0
    @State private var categoryIdx: Int = 0
    @State private var keywordIdx:  Int = 0

    // MARK: – Derived

    private var currentCategory: KeywordCategory { keywordCategories[categoryIdx] }
    private var currentKeyword:  String          { currentCategory.keywords[keywordIdx] }

    private var composedMessage: String {
        String(format: messageTemplates[templateIdx], currentKeyword)
    }

    // Template rows show "…" in place of %@ so the pattern is readable
    private func templateLabel(_ t: String) -> String {
        t.replacingOccurrences(of: "%@", with: "…")
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                templateSection
                categorySection
                keywordSection
                locationSection
            }
            .navigationTitle("Leave an Echo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(store.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
        }
        .interactiveDismissDisabled(store.isSubmitting)
        // When the user switches category, snap keyword back to the first item
        .onChange(of: categoryIdx) { _, _ in keywordIdx = 0 }
    }

    // MARK: – Section 1: Preview

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(composedMessage)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: composedMessage)

                Label(
                    String(format: "%.5f,  %.5f", coordinate.latitude, coordinate.longitude),
                    systemImage: "location.fill"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Echo Preview")
        } footer: {
            Text("This message will be etched at your current map position.")
        }
    }

    // MARK: – Section 2: Template

    private var templateSection: some View {
        Section {
            Picker("Template", selection: $templateIdx) {
                ForEach(messageTemplates.indices, id: \.self) { i in
                    Text(templateLabel(messageTemplates[i])).tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
        } header: {
            Text("Template")
        }
    }

    // MARK: – Section 3: Category

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $categoryIdx) {
                ForEach(keywordCategories.indices, id: \.self) { i in
                    Text(keywordCategories[i].name).tag(i)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Category")
        }
    }

    // MARK: – Section 4: Keyword

    private var keywordSection: some View {
        Section {
            Picker("Keyword", selection: $keywordIdx) {
                ForEach(currentCategory.keywords.indices, id: \.self) { i in
                    Text(currentCategory.keywords[i]).tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
        } header: {
            Text("Keyword  —  \(currentCategory.name)")
        }
    }

    // MARK: – Section 5: Location

    private var locationSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if store.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Etch this Echo", systemImage: "flame.fill")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.orange)
            .foregroundStyle(.white)
            .disabled(store.isSubmitting)
        }
    }

    // MARK: – Toolbar submit (mirrored for accessibility)

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if store.isSubmitting {
                ProgressView().tint(.orange)
            } else {
                Text("Leave")
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
        }
        .disabled(store.isSubmitting)
    }

    // MARK: – Action

    private func submit() async {
        let success = await store.submitMessage(
            content:   composedMessage,
            latitude:  coordinate.latitude,
            longitude: coordinate.longitude
        )
        if success { dismiss() }
    }
}

#Preview {
    LeaveMessageView(
        coordinate: .init(latitude: 31.2304, longitude: 121.4737),
        store: MessageStore()
    )
}
