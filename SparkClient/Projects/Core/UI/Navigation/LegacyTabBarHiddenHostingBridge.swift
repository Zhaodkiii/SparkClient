import SwiftUI
import UIKit

/// iOS 15 bridge: hides the root `UITabBar` while the pushed SwiftUI destination is visible.
///
/// UIKit's `hidesBottomBarWhenPushed` must be set before the push happens, which SwiftUI's
/// `NavigationLink` destination closure does not let us control on iOS 15. Instead, we attach
/// a lightweight child controller to the destination and manage the owning `UITabBarController`
/// visibility during the destination lifecycle.
struct LegacyTabBarHiddenHostingBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LegacyTabBarHiddenBridgeViewController {
        LegacyTabBarHiddenBridgeViewController()
    }

    func updateUIViewController(_ uiViewController: LegacyTabBarHiddenBridgeViewController, context: Context) {
        uiViewController.refreshTabBarVisibilityIfNeeded()
    }
}

private final class LegacyTabBarVisibilityCoordinator {
    static let shared = LegacyTabBarVisibilityCoordinator()

    private struct Entry {
        weak var controller: UITabBarController?
        var retainCount: Int
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var owners: [ObjectIdentifier: ObjectIdentifier] = [:]

    func acquire(owner: ObjectIdentifier, controller: UITabBarController) {
        assert(Thread.isMainThread)
        cleanupReleasedControllers()

        let controllerID = ObjectIdentifier(controller)
        if owners[owner] == controllerID {
            controller.tabBar.isHidden = true
            return
        }

        if let previousControllerID = owners[owner], previousControllerID != controllerID {
            release(owner: owner)
        }

        owners[owner] = controllerID

        var entry = entries[controllerID] ?? Entry(controller: controller, retainCount: 0)
        entry.controller = controller
        entry.retainCount += 1
        entries[controllerID] = entry
        controller.tabBar.isHidden = true
    }

    func release(owner: ObjectIdentifier) {
        assert(Thread.isMainThread)
        cleanupReleasedControllers()

        guard let controllerID = owners.removeValue(forKey: owner),
              var entry = entries[controllerID] else {
            return
        }

        entry.retainCount = max(0, entry.retainCount - 1)
        if entry.retainCount == 0 {
            entry.controller?.tabBar.isHidden = false
            entries.removeValue(forKey: controllerID)
        } else {
            entries[controllerID] = entry
        }
    }

    private func cleanupReleasedControllers() {
        for (controllerID, entry) in entries where entry.controller == nil {
            entries.removeValue(forKey: controllerID)
            owners = owners.filter { $0.value != controllerID }
        }
    }
}

final class LegacyTabBarHiddenBridgeViewController: UIViewController {
    private let ownerID = ObjectIdentifier(LegacyTabBarHiddenBridgeToken())
    private var hasAcquiredHiddenState = false
    private var originalAdditionalSafeAreaInsets: UIEdgeInsets?
    private var originalTabBarControllerAdditionalSafeAreaInsets: UIEdgeInsets?
    private var hasAdjustedBottomSafeArea = false
    nonisolated(unsafe) private var pendingRefreshWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTabBarVisibilityIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshTabBarVisibilityIfNeeded(forceLayoutRefresh: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil

        guard isMovingFromParent || navigationController?.topViewController !== parent else {
            return
        }
        releaseHiddenStateIfNeeded()
    }

    deinit {
        let pendingWorkItem = pendingRefreshWorkItem
        pendingRefreshWorkItem = nil
        pendingWorkItem?.cancel()
        let parentViewController = parent
        let releasedOwnerID = ownerID
        Task { @MainActor in
            LegacyTabBarVisibilityCoordinator.shared.release(owner: releasedOwnerID)
        }

        if let parentViewController {
            scheduleDeferredLayoutRefresh(for: parentViewController)
        }
    }

    func refreshTabBarVisibilityIfNeeded(forceLayoutRefresh: Bool = false) {
        guard let tabBarController,
              let navigationController,
              let parentViewController = parent,
              navigationController.viewControllers.count > 1,
              navigationController.topViewController === parentViewController else {
            releaseHiddenStateIfNeeded()
            return
        }

        LegacyTabBarVisibilityCoordinator.shared.acquire(owner: ownerID, controller: tabBarController)
        hasAcquiredHiddenState = true
        adjustBottomSafeAreaIfNeeded(
            tabBarController: tabBarController,
            for: parentViewController,
            tabBarHeight: resolvedTabBarHeight(from: tabBarController),
            forceLayoutRefresh: forceLayoutRefresh
        )
    }

    private func releaseHiddenStateIfNeeded() {
        guard hasAcquiredHiddenState else { return }
        LegacyTabBarVisibilityCoordinator.shared.release(owner: ownerID)
        hasAcquiredHiddenState = false
        restoreBottomSafeAreaIfNeeded()
    }

    private func adjustBottomSafeAreaIfNeeded(
        tabBarController: UITabBarController,
        for parentViewController: UIViewController,
        tabBarHeight: CGFloat,
        forceLayoutRefresh: Bool
    ) {
        guard tabBarHeight > 0 else { return }

        if originalAdditionalSafeAreaInsets == nil {
            originalAdditionalSafeAreaInsets = parentViewController.additionalSafeAreaInsets
        }
        if originalTabBarControllerAdditionalSafeAreaInsets == nil {
            originalTabBarControllerAdditionalSafeAreaInsets = tabBarController.additionalSafeAreaInsets
        }

        var updatedInsets = originalAdditionalSafeAreaInsets ?? parentViewController.additionalSafeAreaInsets
        updatedInsets.bottom -= tabBarHeight
        var updatedTabControllerInsets = originalTabBarControllerAdditionalSafeAreaInsets ?? tabBarController.additionalSafeAreaInsets
        updatedTabControllerInsets.bottom -= tabBarHeight

        if hasAdjustedBottomSafeArea,
           parentViewController.additionalSafeAreaInsets == updatedInsets,
           tabBarController.additionalSafeAreaInsets == updatedTabControllerInsets,
           forceLayoutRefresh == false {
            return
        }

        tabBarController.additionalSafeAreaInsets = updatedTabControllerInsets
        parentViewController.additionalSafeAreaInsets = updatedInsets
        hasAdjustedBottomSafeArea = true
        refreshLayout(for: parentViewController)
    }

    private func restoreBottomSafeAreaIfNeeded() {
        guard hasAdjustedBottomSafeArea else { return }
        guard let parentViewController = parent else { return }

        if let tabBarController,
           let originalTabBarControllerAdditionalSafeAreaInsets {
            tabBarController.additionalSafeAreaInsets = originalTabBarControllerAdditionalSafeAreaInsets
        }
        if let originalAdditionalSafeAreaInsets {
            parentViewController.additionalSafeAreaInsets = originalAdditionalSafeAreaInsets
        }

        originalTabBarControllerAdditionalSafeAreaInsets = nil
        originalAdditionalSafeAreaInsets = nil
        hasAdjustedBottomSafeArea = false
        refreshLayout(for: parentViewController)
    }

    private func resolvedTabBarHeight(from tabBarController: UITabBarController) -> CGFloat {
        let measuredHeight = tabBarController.tabBar.frame.height
        if measuredHeight > 0 {
            return measuredHeight
        }

        let safeAreaBottomInset = tabBarController.view.safeAreaInsets.bottom
        if safeAreaBottomInset > 0 {
            return 49 + safeAreaBottomInset
        }

        return 49
    }

    private func refreshLayout(for parentViewController: UIViewController) {
        parentViewController.view.setNeedsLayout()
        parentViewController.view.layoutIfNeeded()
        parentViewController.view.setNeedsUpdateConstraints()
        navigationController?.view.setNeedsLayout()
        navigationController?.view.layoutIfNeeded()
        tabBarController?.view.setNeedsLayout()
        tabBarController?.view.layoutIfNeeded()
        view.window?.setNeedsLayout()
        view.window?.layoutIfNeeded()
    }

    private func scheduleDeferredLayoutRefresh(for parentViewController: UIViewController) {
        pendingRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak parentViewController] in
            guard let self, let parentViewController else { return }
            self.refreshLayout(for: parentViewController)
        }
        pendingRefreshWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }
}

private final class LegacyTabBarHiddenBridgeToken {}
