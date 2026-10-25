import SwiftUI

struct LithosBalanceSection: View {
    @ObservedObject var store: LithosBalanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) })) {
                Text(verbatim: "LithosAI")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if store.enabled {
                HStack(spacing: 8) {
                    switch store.state {
                    case .signedOut:
                        Text(store.isSigningOut
                             ? String(localized: "lithos.balance.signingOut", defaultValue: "Signing out…")
                             : String(localized: "lithos.balance.signInHint", defaultValue: "Sign in to see your balance."))
                            .foregroundStyle(.secondary)
                    case .loading:
                        ProgressView().controlSize(.mini)
                        Text(String(localized: "lithos.balance.loading", defaultValue: "Checking balance…"))
                            .foregroundStyle(.secondary)
                    case .loaded(let amount):
                        Text(verbatim: amount)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    case .failed(let message):
                        Text(message)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if store.hasSession {
                        Button(String(localized: "lithos.balance.signOut", defaultValue: "Sign out")) { store.signOut() }
                            .buttonStyle(.link)
                    } else if !store.isRefreshing && !store.isSigningOut {
                        Button(String(localized: "lithos.balance.signIn", defaultValue: "Sign in")) { store.signIn() }
                            .buttonStyle(.link)
                    }
                }
                .font(.system(size: 10.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
