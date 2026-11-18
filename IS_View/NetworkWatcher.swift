import Network

/// Calls `onChange(isSatisfied)` whenever the network path changes (Wi-Fi <-> cellular, VPN/Tailscale up, etc.).
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in self?.onChange?(path.status == .satisfied) }
        monitor.start(queue: DispatchQueue(label: "NetworkWatcher"))
    }
}
