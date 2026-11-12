import AppKit
import SwiftUI
import SharedData

extension LiveIslandExpandedView {
    func timingHeader(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .trailing)
    }

    var titleMenu: some View {
        Menu {
            ForEach(LiveSeries.allCases) { series in
                Button { model.setLiveSeries(series) } label: {
                    if model.liveSeries == series {
                        Label(series.title, systemImage: "checkmark")
                    } else {
                        Text(series.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.headline).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("切换 F1 / WEC 实时数据")
        .accessibilityLabel("\(title)，切换实时数据源")
        .accessibilityIdentifier("liveIsland.seriesMenu")
    }

    var displayMenu: some View {
        Menu {
            Toggle("显示轮胎", isOn: $actions.showTire)
            if snapshot.isWec {
                Toggle("显示虚拟能量", isOn: $actions.showEnergy)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("选择显示的数据")
        .accessibilityLabel("选择显示的数据")
        .accessibilityIdentifier("liveIsland.columns")
    }

    var classTabs: some View {
        HStack(spacing: 2) {
            classTab(id: nil, label: "全部", count: snapshot.drivers.count)
            ForEach(wecClasses, id: \.id) { item in
                classTab(id: item.id, label: item.label, count: item.count)
            }
        }
        .padding(2)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    func classTab(id: String?, label: String, count: Int) -> some View {
        let selected = actions.wecClass == id
        return Button { actions.wecClass = id } label: {
            HStack(spacing: 4) {
                Text(label)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("显示 \(label) 组别")
        .accessibilityLabel("\(label)，\(count) 辆")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("liveIsland.class.\(id ?? "all")")
    }

    var followControls: some View {
        HStack(spacing: 10) {
            if let favorite {
                LiveHelmetView(model: model, driver: favorite, size: 28, isWec: snapshot.isWec)
            }
            Menu {
                Button("不关注") { model.setFavoriteDriver(nil, series: snapshot.isWec ? .wec : .f1) }
                ForEach(LiveIslandLogic.favorites(for: snapshot.isWec ? .wec : .f1, in: model.favoriteDrivers)) { driver in
                    Button { model.setFavoriteDriver(driver.id, name: driver.name, series: snapshot.isWec ? .wec : .f1) } label: {
                        if favoriteID == driver.id {
                            Label(driver.name, systemImage: "checkmark")
                        } else {
                            Text(driver.name)
                        }
                    }
                }
            } label: {
                Image(systemName: favoriteID == nil ? "star" : "star.fill")
                    .foregroundStyle(favoriteID == nil ? Color.secondary : .yellow)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.favoriteDrivers.isEmpty)
            .help("选择或切换关注车手")
            .accessibilityLabel("选择关注车手")
            .accessibilityIdentifier("liveIsland.favoriteDriver")
            if let driver = favorite {
                Text("#\(driver.number) \(driver.name ?? "车手")")
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Text("P\(driver.position.map(String.init) ?? "—") · \(driver.gap ?? "—")")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("No selected")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
    }

    func modeButton(_ value: String, title: String, icon: String) -> some View {
        Button { actions.mode = value } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(mode == value ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityAddTraits(mode == value ? .isSelected : [])
            .accessibilityIdentifier("liveIsland.mode.\(value)")
    }
}
