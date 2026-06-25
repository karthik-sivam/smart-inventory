import SwiftUI
import SwiftData

struct TemplatesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ItemTemplate.name) private var templates: [ItemTemplate]
    @Query private var allItems: [InventoryItem]

    @State private var showingCreateSheet = false
    @State private var templateToEdit: ItemTemplate?
    @State private var templateToDelete: ItemTemplate?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No Templates Yet",
                    systemImage: "doc.on.doc",
                    description: Text("Save an item as a template from the Edit Item screen, or create one from scratch below.")
                )
            } else {
                List {
                    ForEach(templates) { template in
                        TemplateRow(
                            template: template,
                            linkedItemCount: linkedItems(for: template).count
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { templateToEdit = template }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                templateToDelete = template
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                templateToEdit = template
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Item Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Template")
                .accessibilityIdentifier("createTemplateButton")
            }
        }
        .sheet(item: $templateToEdit) { template in
            TemplateEditSheet(template: template, isNew: false)
        }
        .sheet(isPresented: $showingCreateSheet) {
            TemplateEditSheet(template: nil, isNew: true)
        }
        .confirmationDialog(deleteConfirmationTitle, isPresented: $showingDeleteConfirmation,
                            presenting: templateToDelete) { template in
            Button("Delete Template", role: .destructive) {
                deleteTemplate(template)
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: { template in
            Text(deleteConfirmationMessage(for: template))
        }
    }

    // MARK: - Helpers

    private func linkedItems(for template: ItemTemplate) -> [InventoryItem] {
        allItems.filter { $0.createdFromTemplateId == template.id }
    }

    private var deleteConfirmationTitle: String {
        guard let template = templateToDelete else { return "Delete Template?" }
        let count = linkedItems(for: template).count
        return count > 0 ? "Delete Template?" : "Delete \"\(template.name)\"?"
    }

    private func deleteConfirmationMessage(for template: ItemTemplate) -> String {
        let items = linkedItems(for: template)
        if items.isEmpty {
            return "This template has not been used to create any items. It will be permanently removed."
        }
        let storageNames = Array(Set(items.compactMap { $0.storage?.name })).sorted()
        let storageList = storageNames.prefix(3).joined(separator: ", ")
        let overflow = storageNames.count > 3 ? " and \(storageNames.count - 3) more" : ""
        return "\(items.count) item\(items.count == 1 ? "" : "s") \(items.count == 1 ? "was" : "were") created using this template — found in \(storageList)\(overflow). Deleting the template will not affect those items."
    }

    private func deleteTemplate(_ template: ItemTemplate) {
        FirestoreManager.shared.deleteTemplate(template)
        modelContext.delete(template)
        modelContext.safeSave(context: "deleteTemplate")
        templateToDelete = nil
    }
}

// MARK: - TemplateRow

private struct TemplateRow: View {
    let template: ItemTemplate
    let linkedItemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.name)
                    .fontWeight(.semibold)
                Spacer()
                if linkedItemCount > 0 {
                    Text("\(linkedItemCount) item\(linkedItemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }
            HStack(spacing: 8) {
                Text(template.category)
                Text("·")
                Text(template.uomName)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - TemplateEditSheet

struct TemplateEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var uoms: [UOM]
    @Query private var allItems: [InventoryItem]

    var template: ItemTemplate?
    let isNew: Bool

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var category: String = "Uncategorised"
    @State private var selectedUOM: UOM? = nil
    @State private var defaultMinQty: String = ""
    @State private var defaultMaxQty: String = ""
    @State private var showingEditConfirmation = false

    private var linkedItemCount: Int {
        guard let template else { return 0 }
        return allItems.filter { $0.createdFromTemplateId == template.id }.count
    }

    private var linkedStorageNames: [String] {
        guard let template else { return [] }
        let items = allItems.filter { $0.createdFromTemplateId == template.id }
        return Array(Set(items.compactMap { $0.storage?.name })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Details") {
                    TextField("Template Name", text: $name)
                        .accessibilityIdentifier("templateNameField")
                    TextField("Description (optional)", text: $description)
                }

                Section("Defaults") {
                    Picker("Category", selection: $category) {
                        ForEach(InventoryItem.predefinedCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Unit of Measure", selection: $selectedUOM) {
                        Text("None").tag(Optional<UOM>(nil))
                        ForEach(uoms) { uom in
                            Text("\(uom.name) (\(uom.symbol))").tag(Optional(uom))
                        }
                    }
                    .pickerStyle(.navigationLink)

                    TextField("Default Min Qty (optional)", text: $defaultMinQty)
                        .keyboardType(.decimalPad)
                    TextField("Default Max Qty (optional)", text: $defaultMaxQty)
                        .keyboardType(.decimalPad)
                }

                if !isNew && linkedItemCount > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Used by \(linkedItemCount) item\(linkedItemCount == 1 ? "" : "s")",
                                  systemImage: "info.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            let names = linkedStorageNames.prefix(3).joined(separator: ", ")
                            let overflow = linkedStorageNames.count > 3
                                ? " and \(linkedStorageNames.count - 3) more" : ""
                            Text("Found in: \(names)\(overflow). Editing this template will not change those existing items — it only affects new items created from it going forward.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(isNew ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if !isNew && linkedItemCount > 0 {
                            showingEditConfirmation = true
                        } else {
                            saveTemplate()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Edit Template?", isPresented: $showingEditConfirmation) {
                Button("Save Changes") { saveTemplate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This template was used to create \(linkedItemCount) item\(linkedItemCount == 1 ? "" : "s"). Editing it won't change those existing items — only new items created from this template going forward.")
            }
            .onAppear { loadFromTemplate() }
        }
    }

    private func loadFromTemplate() {
        guard let template else {
            if selectedUOM == nil {
                selectedUOM = uoms.first(where: { $0.isDefault })
            }
            return
        }
        name = template.name
        description = template.templateDescription
        category = template.category
        selectedUOM = uoms.first { $0.symbol == template.uomSymbol }
        defaultMinQty = template.defaultMinQty > 0 ? template.defaultMinQty.smartFormatted : ""
        defaultMaxQty = template.defaultMaxQty > 0 ? template.defaultMaxQty.smartFormatted : ""
    }

    private func saveTemplate() {
        if isNew {
            let newTemplate = ItemTemplate(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                category: category,
                uomSymbol: selectedUOM?.symbol ?? "pcs",
                uomName: selectedUOM?.name ?? "Pieces",
                defaultMinQty: Double(defaultMinQty) ?? 0,
                defaultMaxQty: Double(defaultMaxQty) ?? 0
            )
            modelContext.insert(newTemplate)
            modelContext.safeSave(context: "createTemplate")
            FirestoreManager.shared.syncTemplate(newTemplate)
        } else if let template {
            template.name = name.trimmingCharacters(in: .whitespaces)
            template.templateDescription = description
            template.category = category
            template.uomSymbol = selectedUOM?.symbol ?? template.uomSymbol
            template.uomName = selectedUOM?.name ?? template.uomName
            template.defaultMinQty = Double(defaultMinQty) ?? 0
            template.defaultMaxQty = Double(defaultMaxQty) ?? 0
            modelContext.safeSave(context: "editTemplate")
            FirestoreManager.shared.syncTemplate(template)
        }
        dismiss()
    }
}

extension ItemTemplate: Identifiable {}
