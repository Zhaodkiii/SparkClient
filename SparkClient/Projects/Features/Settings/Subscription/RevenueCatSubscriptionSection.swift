import Combine
import RevenueCat
import RevenueCatUI
import SwiftUI

@MainActor
final class RevenueCatPaywallCoordinator: ObservableObject {
    @Published private(set) var offering: Offering?
    @Published private(set) var hasProEntitlement = false

    func present(offering: Offering) {
        guard self.offering == nil else { return }
        self.offering = offering
    }

    func dismiss() {
        offering = nil
    }

    func apply(_ customerInfo: CustomerInfo) {
        hasProEntitlement = customerInfo.entitlements
            .activeInCurrentEnvironment[RevenueCatConfiguration.entitlementIdentifier] != nil
    }
}

@MainActor
final class RevenueCatSubscriptionViewModel: ObservableObject {
    @Published private(set) var hasProEntitlement = false
    @Published private(set) var entitlementExpirationDate: Date?
    @Published private(set) var offering: Offering?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRestoring = false
    @Published var message: String?

    func refresh() async -> CustomerInfo? {
        guard RevenueCatClient.shared.isConfigured else { return nil }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let customerInfo = Purchases.shared.customerInfo()
            async let offerings = Purchases.shared.offerings()
            let loadedCustomerInfo = try await customerInfo
            apply(loadedCustomerInfo)
            let loadedOfferings = try await offerings
            offering = loadedOfferings.offering(identifier: RevenueCatConfiguration.offeringIdentifier)
            return loadedCustomerInfo
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    func restorePurchases() async -> CustomerInfo? {
        guard RevenueCatClient.shared.isConfigured else { return nil }
        isRestoring = true
        defer { isRestoring = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            apply(customerInfo)
            message = hasProEntitlement
                ? L10n.text("settings.subscription.restore_success")
                : L10n.text("settings.subscription.restore_empty")
            return customerInfo
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    func apply(_ customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements
            .all[RevenueCatConfiguration.entitlementIdentifier]
        hasProEntitlement = entitlement?.isActive == true
        entitlementExpirationDate = entitlement?.expirationDate
    }
}

struct RevenueCatSubscriptionSection: View {
    @EnvironmentObject private var paywallCoordinator: RevenueCatPaywallCoordinator
    @EnvironmentObject private var subscriptionSyncCoordinator: SubscriptionSyncCoordinator
    @StateObject private var viewModel = RevenueCatSubscriptionViewModel()
    @State private var isOpeningPaywall = false

    var body: some View {
        Section {
            Button {
                guard subscriptionSyncCoordinator.canPurchaseOrRestore else { return }
                guard !viewModel.isRefreshing, !isOpeningPaywall, paywallCoordinator.offering == nil else { return }

                isOpeningPaywall = true
                Task {
                    let customerInfo = await viewModel.refresh()
                    if let customerInfo {
                        paywallCoordinator.apply(customerInfo)
                    }

                    if !Task.isCancelled, let offering = viewModel.offering {
                        paywallCoordinator.present(offering: offering)
                    }

                    isOpeningPaywall = false
                }
            } label: {
                HStack {
                    Label(
                        L10n.text("settings.subscription.open_paywall"),
                        systemImage: "crown"
                    )
                    Spacer()
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(
                            L10n.text(
                                paywallCoordinator.hasProEntitlement
                                    ? "settings.subscription.status_active"
                                    : "settings.subscription.status_inactive"
                            )
                        )
                        .foregroundStyle(paywallCoordinator.hasProEntitlement ? .green : .secondary)
                    }
                }
            }
            .disabled(viewModel.isRefreshing || isOpeningPaywall || paywallCoordinator.offering != nil || !subscriptionSyncCoordinator.canPurchaseOrRestore)
            .task {
                if let customerInfo = await viewModel.refresh() {
                    paywallCoordinator.apply(customerInfo)
                }
            }

            Button {
                Task {
                    guard subscriptionSyncCoordinator.canPurchaseOrRestore else { return }
                    if let customerInfo = await viewModel.restorePurchases() {
                        paywallCoordinator.apply(customerInfo)
                        subscriptionSyncCoordinator.synchronizeIfAllowed(reason: .restoreCompleted, force: true)
                    }
                }
            } label: {
                if viewModel.isRestoring {
                    ProgressView()
                } else {
                    Label(
                        L10n.text("settings.subscription.restore"),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .disabled(viewModel.isRestoring || !subscriptionSyncCoordinator.canPurchaseOrRestore)

            Button {
                subscriptionSyncCoordinator.synchronizeIfAllowed(reason: .manualRefresh, force: true)
            } label: {
                Label(L10n.text("settings.subscription.refresh_status"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!subscriptionSyncCoordinator.canPurchaseOrRestore)

            if let syncMessage {
                Text(syncMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.text("settings.subscription.section"))
        } footer: {
            Text(L10n.text("settings.subscription.footer"))
        }
    }

    private var syncMessage: String? {
        switch subscriptionSyncCoordinator.identityState {
        case .unbound, .binding:
            return L10n.text("settings.subscription.binding_required")
        case .failed:
            return L10n.text("settings.subscription.binding_required")
        case .bound:
            break
        }
        switch subscriptionSyncCoordinator.syncState {
        case .idle:
            return nil
        case .syncing:
            return L10n.text("settings.subscription.syncing")
        case .pendingRetry:
            return L10n.text("settings.subscription.sync_pending")
        case .failed:
            return L10n.text("settings.subscription.sync_pending")
        }
    }
}
