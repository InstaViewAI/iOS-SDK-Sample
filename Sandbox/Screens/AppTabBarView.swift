//
//  AppTabBarView.swift
//  Sandbox
//
//  Signed-in shell. The tab bar lives inside one pilot route, so pushing a
//  camera or pairing screen covers it rather than nesting inside a tab.
//

import SwiftUI

struct AppTabBarView: View {
    @ObservedObject var sharedData: SharedDataStore
    @ObservedObject var spaceDataStore: SpaceDataStore
    @ObservedObject var eventsDataStore: EventsDataStore
    @ObservedObject var proSecurityStore: ProSecurityStore

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                ZStack {
                    switch sharedData.tabSelection {
                    case .home:
                        HomeScreen(viewModel: .init(sharedData: sharedData,
                                                    spaceDataStore: spaceDataStore,
                                                    eventsDataStore: eventsDataStore))
                    case .events:
                        EventsScreen(viewModel: .init(sharedData: sharedData,
                                                      eventsDataStore: eventsDataStore))
                    case .security:
                        ProSecurityScreen(viewModel: .init(store: proSecurityStore))
                    case .settings:
                        SettingsScreen(sharedData: sharedData)
                    }
                }
                .frame(maxHeight: .infinity)

                tabBar
            }
        }
    }

    private var tabBar: some View {
        HStack {
            tabItem(.home, icon: "house.fill", title: "Home")
            tabItem(.events, icon: "clock.fill", title: "Events")
            tabItem(.security, icon: "shield.lefthalf.filled", title: "Security")
            tabItem(.settings, icon: "gearshape.fill", title: "Settings")
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            AppColors.surface
                .overlay(Rectangle().fill(AppColors.border).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(_ tab: SharedDataStore.Tab, icon: String, title: String) -> some View {
        let selected = sharedData.tabSelection == tab
        return Button {
            sharedData.tabSelection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(AppFont.caption(10))
            }
            .foregroundColor(selected ? AppColors.primary : AppColors.textDisabled)
            .frame(maxWidth: .infinity)
        }
    }
}
