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
private final class RevenueCatSubscriptionViewModel: ObservableObject {
    @Published private(set) var hasProEntitlement = false
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
        hasProEntitlement = customerInfo.entitlements
            .activeInCurrentEnvironment[RevenueCatConfiguration.entitlementIdentifier] != nil
    }
}

struct RevenueCatSubscriptionSection: View {
    @EnvironmentObject private var paywallCoordinator: RevenueCatPaywallCoordinator
    @StateObject private var viewModel = RevenueCatSubscriptionViewModel()
    @State private var isOpeningPaywall = false

    var body: some View {
        Section {
            Button {
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
            .disabled(viewModel.isRefreshing || isOpeningPaywall || paywallCoordinator.offering != nil)
            .task {
                if let customerInfo = await viewModel.refresh() {
                    paywallCoordinator.apply(customerInfo)
                }
            }

            Button {
                Task {
                    if let customerInfo = await viewModel.restorePurchases() {
                        paywallCoordinator.apply(customerInfo)
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
            .disabled(viewModel.isRestoring)

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
}
