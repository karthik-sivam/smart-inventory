import SwiftUI
import FirebaseAuth

enum BusinessProfilePresentationMode: Equatable {
    case requiredPrompt(audience: String)
    case edit

    var isRequired: Bool {
        if case .requiredPrompt = self { return true }
        return false
    }

    var analyticsSource: String {
        switch self {
        case .requiredPrompt: return "required_prompt"
        case .edit: return "profile"
        }
    }

    var analyticsAudience: String {
        switch self {
        case .requiredPrompt(let audience): return audience
        case .edit: return "owner"
        }
    }
}

/// Compact, versioned business-profile form. Business type and State are
/// required; phone is optional and cannot be saved without explicit consent.
///
/// Design notes:
/// - Business type is a tap-once tile grid, not a hidden menu. It is the single
///   signal we most want and the audience is often low-digital-literacy.
/// - State opens a searchable sheet — 36 entries is far too many for a menu.
/// - The save button explains *why* it is disabled instead of failing silently.
struct BusinessProfileView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var firestoreManager: FirestoreManager

    let mode: BusinessProfilePresentationMode
    let onSaved: (BusinessProfile) -> Void

    private enum Field: Hashable {
        case businessName
        case otherBusinessType
        case state
        case city
        case phone
    }

    @State private var businessNameInput: String
    @State private var selectedBusinessType: BusinessType?
    @State private var otherBusinessType: String
    @State private var selectedCountry: String
    @State private var selectedState: String
    @State private var cityInput: String
    @State private var phoneInput: String
    @State private var contactConsent: Bool
    @State private var isLoading: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var startedAt = Date()
    @State private var showStatePicker = false
    @State private var showCountryPicker = false
    @FocusState private var focusedField: Field?

    private let tileColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        isPresented: Binding<Bool>,
        mode: BusinessProfilePresentationMode,
        existingProfile: BusinessProfile? = nil,
        onSaved: @escaping (BusinessProfile) -> Void = { _ in }
    ) {
        _isPresented = isPresented
        self.mode = mode
        self.onSaved = onSaved
        _businessNameInput = State(initialValue: existingProfile?.businessName ?? "")
        _selectedBusinessType = State(initialValue: existingProfile?.businessType)
        _otherBusinessType = State(initialValue: existingProfile?.otherBusinessType ?? "")
        _selectedCountry = State(initialValue: existingProfile?.country
                                 ?? BusinessProfileOptions.defaultCountryCode())
        _selectedState = State(initialValue: existingProfile?.state ?? "")
        _cityInput = State(initialValue: existingProfile?.city ?? "")
        _phoneInput = State(initialValue: existingProfile?.phoneNumber ?? "")
        _contactConsent = State(initialValue: existingProfile?.contactConsent ?? false)
        _isLoading = State(initialValue: mode == .edit && existingProfile == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                Spacer()
                ProgressView(L("businessProfile.loading", "Loading business details…"))
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if mode.isRequired { introduction }
                        businessTypeSection
                        stateSection
                        phoneSection
                        if let errorMessage { errorCard(errorMessage) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, mode.isRequired ? 16 : 20)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)

                saveBar
            }
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled(mode.isRequired)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("businessProfile.done", "Done")) { focusedField = nil }
            }
        }
        .sheet(isPresented: $showStatePicker) {
            SubdivisionSelectionSheet(
                selectedValue: $selectedState,
                options: subdivisionOptions ?? [],
                title: isIndia ? L("businessProfile.stateTitle", "State / UT")
                               : L("businessProfile.regionTitle", "State / Region"),
                searchPrompt: isIndia ? L("businessProfile.stateSearch", "Search State or UT")
                                      : L("businessProfile.regionSearch", "Search state or region")
            )
        }
        .sheet(isPresented: $showCountryPicker) {
            // The subdivision is cleared HERE, on the user's own selection —
            // deliberately not in an `.onChange(of: selectedCountry)`.
            // `.onChange` also fires for programmatic assignment, and it runs on
            // the next view update rather than at the assignment. Loading an
            // existing profile sets country then state, so the handler ran after
            // both and wiped the freshly loaded State every time the stored
            // country differed from the device default — which is exactly the
            // case for profiles saved before the country field existed, since
            // those read back as "IN". A boolean "am I loading" guard cannot fix
            // that: it would already be reset by the time the handler ran.
            CountrySelectionSheet(selectedCountry: selectedCountry) { newCode in
                guard newCode != selectedCountry else { return }
                selectedCountry = newCode
                selectedState = ""
                if focusedField == .state { focusedField = nil }
            }
        }
        .task { await loadExistingProfileIfNeeded() }
        .onChange(of: selectedBusinessType) { _, newValue in
            if newValue != .other {
                otherBusinessType = ""
                if focusedField == .otherBusinessType { focusedField = nil }
            } else {
                focusedField = .otherBusinessType
            }
        }
        .onChange(of: otherBusinessType) { _, newValue in
            if newValue.count > BusinessProfileValidation.maximumOtherBusinessTypeLength {
                otherBusinessType = String(newValue.prefix(BusinessProfileValidation.maximumOtherBusinessTypeLength))
            }
        }
        .onChange(of: businessNameInput) { _, newValue in
            if newValue.count > BusinessProfileValidation.maximumBusinessNameLength {
                businessNameInput = String(newValue.prefix(BusinessProfileValidation.maximumBusinessNameLength))
            }
        }
        .onChange(of: selectedState) { _, newValue in
            if !isIndia, newValue.count > BusinessProfileValidation.maximumStateLength {
                selectedState = String(newValue.prefix(BusinessProfileValidation.maximumStateLength))
            }
        }
        .onChange(of: cityInput) { _, newValue in
            if newValue.count > BusinessProfileValidation.maximumCityLength {
                cityInput = String(newValue.prefix(BusinessProfileValidation.maximumCityLength))
            }
        }
        .onChange(of: phoneInput) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contactConsent = false
            }
        }
        .onChange(of: focusedField) { _, newValue in
            // The State list is India-only, so almost every number starts +91.
            // Seed the country code rather than letting people fail validation
            // by typing a bare 10-digit number. It stays fully editable.
            if newValue == .phone,
               phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                phoneInput = "+91 "
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode.isRequired ? L("businessProfile.titleRequired", "Tell us about your business") : L("businessProfile.titleEdit", "Business details"))
                    .font(.title3.weight(.bold))
                Spacer(minLength: 12)
                if !mode.isRequired {
                    Button(L("businessProfile.cancel", "Cancel")) { isPresented = false }
                        .accessibilityIdentifier("businessProfileCancel")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(L("businessProfile.intro", "Two quick answers so Stoqly can set up the right categories, alerts, and support for your shop. Takes about 10 seconds."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Business type

    private var businessTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("businessProfile.typeSection", "What kind of business?"), badge: L("businessProfile.badgeRequired", "Required"), isSatisfied: isBusinessTypeSatisfied)

            LazyVGrid(columns: tileColumns, spacing: 10) {
                ForEach(BusinessType.allCases) { type in
                    businessTypeTile(type)
                }
            }
            .accessibilityIdentifier("businessTypePicker")

            if selectedBusinessType == .other {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(L("businessProfile.otherPlaceholder", "Describe your business"), text: $otherBusinessType)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .otherBusinessType)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .accessibilityIdentifier("otherBusinessTypeField")

                    Text(verbatim: "\(otherBusinessType.count)/\(BusinessProfileValidation.maximumOtherBusinessTypeLength)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                Image(systemName: "signature")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(businessNameInput.isEmpty ? Color.secondary : Color.accentColor)
                    .frame(width: 22)

                TextField(L("businessProfile.namePlaceholder", "Business name (optional)"), text: $businessNameInput)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .businessName)
                    .accessibilityIdentifier("businessNameField")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .animation(.easeInOut(duration: 0.18), value: selectedBusinessType)
    }

    private func businessTypeTile(_ type: BusinessType) -> some View {
        let isSelected = selectedBusinessType == type
        return Button {
            focusedField = nil
            selectedBusinessType = type
        } label: {
            HStack(spacing: 10) {
                Image(systemName: type.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                Text(type.localizedShortName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color(.separator),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("businessType_\(type.rawValue)")
        .accessibilityLabel(type.localizedDisplayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - State

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("businessProfile.locationSection", "Where is it?"), badge: L("businessProfile.badgeRequired", "Required"), isSatisfied: isStateSatisfied)

            pickerRow(icon: "globe",
                      title: BusinessProfileOptions.countryName(for: selectedCountry),
                      isFilled: true,
                      identifier: "businessCountryPicker") {
                showCountryPicker = true
            }

            if subdivisionOptions != nil {
                pickerRow(icon: "mappin.and.ellipse",
                          title: selectedState.isEmpty
                              ? (isIndia
                                 ? L("businessProfile.statePlaceholder", "Select State / Union Territory")
                                 : L("businessProfile.regionPlaceholder", "State / Province / Region"))
                              : selectedState,
                          isFilled: !selectedState.isEmpty,
                          identifier: "businessStatePicker") {
                    showStatePicker = true
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selectedState.isEmpty ? Color.secondary : Color.accentColor)
                        .frame(width: 22)

                    TextField(L("businessProfile.regionPlaceholder", "State / Province / Region"),
                              text: $selectedState)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .state)
                        .accessibilityIdentifier("businessRegionField")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(selectedState.isEmpty ? Color(.separator) : Color.accentColor.opacity(0.45),
                                lineWidth: selectedState.isEmpty ? 0.5 : 1)
                )
            }

            HStack(spacing: 12) {
                Image(systemName: "building.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(cityInput.isEmpty ? Color.secondary : Color.accentColor)
                    .frame(width: 22)

                TextField(L("businessProfile.cityPlaceholder", "City or town (optional)"), text: $cityInput)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.addressCity)
                    .focused($focusedField, equals: .city)
                    .accessibilityIdentifier("businessCityField")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Phone

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("businessProfile.phoneSection", "Phone / WhatsApp"), badge: L("businessProfile.badgeOptional", "Optional"), isSatisfied: false)

            VStack(alignment: .leading, spacing: 12) {
                TextField(L("businessProfile.phonePlaceholder", "+91 98765 43210"), text: $phoneInput)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($focusedField, equals: .phone)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(showsPhoneFormatError ? Color.red : Color(.separator),
                                    lineWidth: showsPhoneFormatError ? 1 : 0.5)
                    )
                    .accessibilityIdentifier("businessPhoneField")

                if showsPhoneFormatError {
                    inlineNote(L("businessProfile.phoneFormatError", "Add the country code, for example +91 98765 43210."),
                               systemImage: "exclamationmark.circle.fill",
                               tint: .red)
                } else {
                    inlineNote(L("businessProfile.phoneHelp", "So we can help you on WhatsApp if you get stuck. No OTP, no spam."),
                               systemImage: "bubble.left.and.text.bubble.right.fill",
                               tint: .secondary)
                }

                if hasPhoneInput {
                    Divider()

                    Toggle(isOn: $contactConsent) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("businessProfile.consentTitle", "Stoqly may contact me here"))
                                .font(.subheadline.weight(.medium))
                            Text(L("businessProfile.consentDetail", "Phone or WhatsApp — for support, product research, and updates. Clear the number any time to withdraw consent."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Color.accentColor)
                    .accessibilityIdentifier("businessContactConsentToggle")
                }

                Divider()

                inlineNote(L("businessProfile.privacyNote", "Saved to your Stoqly account only. Your number is never sent to analytics or ads."),
                           systemImage: "lock.shield.fill",
                           tint: .secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.18), value: hasPhoneInput)
            .animation(.easeInOut(duration: 0.18), value: contactConsent)
        }
    }

    // MARK: - Shared pieces

    private var isIndia: Bool { selectedCountry == BusinessProfileOptions.indiaRegionCode }

    /// nil when the selected country has no curated list — the form then shows a
    /// plain text field instead of a picker.
    private var subdivisionOptions: [String]? {
        BusinessProfileOptions.subdivisions(for: selectedCountry)
    }

    private func pickerRow(icon: String,
                           title: String,
                           isFilled: Bool,
                           identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            focusedField = nil
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isFilled ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.body)
                    .foregroundStyle(isFilled ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFilled ? Color.accentColor.opacity(0.45) : Color(.separator),
                            lineWidth: isFilled ? 1 : 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    private func sectionHeader(_ title: String, badge: String, isSatisfied: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)

            if isSatisfied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            } else {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    private func inlineNote(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(tint == .red ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("businessProfileError")
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            if let blockingHint, !isSaving {
                Text(blockingHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("businessProfileHint")
            }

            Button(action: save) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    }
                    Text(isSaving
                         ? L("businessProfile.saving", "Saving…")
                         : (mode.isRequired ? L("businessProfile.saveContinue", "Save and continue") : L("businessProfile.saveChanges", "Save changes")))
                        .font(.body.weight(.semibold))
                }
                // A disabled `.borderedProminent` renders as near-invisible grey
                // on grey, and a faded accent fill puts white text below the
                // contrast floor — so the blocked state uses a neutral fill with
                // a legible secondary label instead.
                .foregroundStyle(isValid ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    isValid ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemFill)),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isValid || isSaving)
            .accessibilityIdentifier("saveBusinessProfile")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Derived state

    private var hasPhoneInput: Bool {
        !phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedPhone: String? {
        BusinessProfileValidation.normalizedPhoneNumber(from: phoneInput)
    }

    /// "+91 " is a seeded prefix, not a real entry — do not scold the user for it.
    private var showsPhoneFormatError: Bool {
        guard hasPhoneInput, normalizedPhone == nil else { return false }
        return phoneInput.trimmingCharacters(in: .whitespacesAndNewlines) != "+91"
    }

    private var isBusinessTypeSatisfied: Bool {
        guard let selectedBusinessType else { return false }
        guard selectedBusinessType == .other else { return true }
        let custom = otherBusinessType.trimmingCharacters(in: .whitespacesAndNewlines)
        return !custom.isEmpty && custom.count <= BusinessProfileValidation.maximumOtherBusinessTypeLength
    }

    private var isStateSatisfied: Bool {
        BusinessProfileValidation.isValidState(selectedState, country: selectedCountry)
    }

    /// Explains a disabled save button instead of leaving the user stuck.
    private var blockingHint: String? {
        if selectedBusinessType == nil { return L("businessProfile.hintType", "Pick your business type to continue.") }
        if selectedBusinessType == .other, !isBusinessTypeSatisfied {
            return L("businessProfile.hintOther", "Describe your business in a few words to continue.")
        }
        if !isStateSatisfied {
            return isIndia
                ? L("businessProfile.hintState", "Choose your State or Union Territory to continue.")
                : L("businessProfile.hintRegion", "Enter your state, province, or region to continue.")
        }
        if hasPhoneInput, normalizedPhone == nil {
            return L("businessProfile.hintPhone", "Fix the phone number, or clear it — it is optional.")
        }
        if hasPhoneInput, !contactConsent {
            return L("businessProfile.hintConsent", "Turn on contact consent, or clear the phone number.")
        }
        return nil
    }

    private var isValid: Bool {
        BusinessProfileValidation.isValid(
            businessType: selectedBusinessType,
            otherBusinessType: otherBusinessType,
            country: selectedCountry,
            state: selectedState,
            phoneInput: phoneInput,
            contactConsent: contactConsent
        )
    }

    // MARK: - Load / save

    private func loadExistingProfileIfNeeded() async {
        guard mode == .edit, isLoading else { return }
        do {
            if let profile = try await firestoreManager.fetchBusinessProfile() {
                businessNameInput = profile.businessName ?? ""
                selectedBusinessType = profile.businessType
                otherBusinessType = profile.otherBusinessType ?? ""
                selectedCountry = profile.country
                selectedState = profile.state
                cityInput = profile.city ?? ""
                phoneInput = profile.phoneNumber ?? ""
                contactConsent = profile.contactConsent
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = L("businessProfile.loadError", "We couldn't load your business details. You can still enter them again and save.")
        }
    }

    private func save() {
        guard isValid, let selectedBusinessType else { return }
        focusedField = nil
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let profile = try await firestoreManager.saveBusinessProfile(
                    businessName: businessNameInput,
                    businessType: selectedBusinessType,
                    otherBusinessType: selectedBusinessType == .other ? otherBusinessType : nil,
                    country: selectedCountry,
                    state: selectedState,
                    city: cityInput,
                    phoneNumber: hasPhoneInput ? phoneInput : nil,
                    contactConsent: hasPhoneInput && contactConsent
                )

                if let uid = Auth.auth().currentUser?.uid {
                    AnalyticsManager.shared.identifyBusinessProfile(userId: uid, profile: profile)
                }

                switch mode {
                case .requiredPrompt:
                    let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                    AnalyticsManager.shared.track(.businessProfileCompleted(
                        source: mode.analyticsSource,
                        audience: mode.analyticsAudience,
                        businessType: profile.businessType.rawValue,
                        state: profile.state,
                        city: profile.city.flatMap {
                            BusinessProfileValidation.analyticsCity(from: $0)
                        },
                        hasPhone: profile.phoneNumber != nil,
                        contactConsent: profile.contactConsent,
                        durationMs: durationMs
                    ))
                case .edit:
                    AnalyticsManager.shared.track(.businessProfileUpdated(
                        source: mode.analyticsSource,
                        businessType: profile.businessType.rawValue,
                        state: profile.state,
                        city: profile.city.flatMap {
                            BusinessProfileValidation.analyticsCity(from: $0)
                        },
                        hasPhone: profile.phoneNumber != nil,
                        contactConsent: profile.contactConsent
                    ))
                }

                isSaving = false
                onSaved(profile)
                isPresented = false
            } catch {
                isSaving = false
                errorMessage = L("businessProfile.saveError", "We couldn't save these details. Check your connection and tap Save again.")
                AnalyticsManager.shared.track(.businessProfileSaveFailed(source: mode.analyticsSource))
            }
        }
    }
}

/// Searchable subdivision picker, reused for every country that has a curated
/// list. Long lists (58 Algerian wilayas, 51 US states) make a menu unusable.
///
/// The "use what I typed" row is the safety net: these lists are hand-maintained,
/// so a missing or renamed subdivision must still be enterable. Without it an
/// incomplete list would silently recreate the lockout this whole screen exists
/// to avoid.
private struct SubdivisionSelectionSheet: View {
    @Binding var selectedValue: String
    let options: [String]
    let title: String
    let searchPrompt: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [String] {
        guard !trimmedQuery.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// Offer the typed value only when it is genuinely not in the list.
    private var showsCustomOption: Bool {
        !trimmedQuery.isEmpty
            && !options.contains { $0.localizedCaseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(matches, id: \.self) { option in
                    Button {
                        selectedValue = option
                        dismiss()
                    } label: {
                        HStack {
                            Text(option).foregroundStyle(.primary)
                            Spacer()
                            if option == selectedValue {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityIdentifier("subdivision_\(option)")
                }

                if showsCustomOption {
                    Button {
                        selectedValue = trimmedQuery
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(String(format: L("businessProfile.useTyped", "Use \"%@\""),
                                        trimmedQuery))
                                .foregroundStyle(.primary)
                        }
                    }
                    .accessibilityIdentifier("subdivisionUseTyped")
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: searchPrompt)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("businessProfile.cancel", "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Searchable ISO country picker. Same shape as the State sheet — ~250 entries
/// makes a menu unusable.
private struct CountrySelectionSheet: View {
    let selectedCountry: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [(code: String, name: String)] {
        let all = BusinessProfileOptions.countryCodes
            .map { (code: $0, name: BusinessProfileOptions.countryName(for: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(matches, id: \.code) { entry in
                    Button {
                        onSelect(entry.code)
                        dismiss()
                    } label: {
                        HStack {
                            Text(entry.name).foregroundStyle(.primary)
                            Spacer()
                            if entry.code == selectedCountry {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityIdentifier("country_\(entry.code)")
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: L("businessProfile.countrySearch", "Search country"))
            .navigationTitle(L("businessProfile.countryTitle", "Country"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("businessProfile.cancel", "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Required") {
    BusinessProfileView(
        isPresented: .constant(true),
        mode: .requiredPrompt(audience: "new_user")
    )
    .environmentObject(FirestoreManager.shared)
}

#Preview("Edit") {
    BusinessProfileView(
        isPresented: .constant(true),
        mode: .edit,
        existingProfile: BusinessProfile(
            schemaVersion: 1,
            businessName: "Devi Medicals",
            businessType: .pharmacy,
            otherBusinessType: nil,
            country: "IN",
            state: "Kerala",
            city: "Kochi",
            phoneNumber: "+919876543210",
            contactConsent: true,
            completedAt: Date()
        )
    )
    .environmentObject(FirestoreManager.shared)
}
