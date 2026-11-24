import Darwin
import Foundation

/// 原生终止端口所属进程的工具，不调用外部 `kill` 命令。
enum PortProcessTerminator {
    enum Outcome: Equatable, Sendable {
        case terminated
        case alreadyExited
        case permissionDenied
        case protectedProcess
        case failed(Int32)
    }

    typealias SignalSender = @Sendable (pid_t, Int32) -> Int32

    /// 向指定 PID 发送 `SIGTERM` 优雅终止。
    /// 禁止终止 `pid <= 1` 或当前 Peek 进程本身。
    static func terminate(
        pid: Int32,
        currentPID: Int32 = getpid(),
        sendSignal: SignalSender = { Darwin.kill($0, $1) }
    ) -> Outcome {
        guard pid > 1, pid != currentPID else {
            return .protectedProcess
        }
        let result = sendSignal(pid, SIGTERM)
        if result == 0 {
            return .terminated
        }
        let err = errno
        switch err {
        case ESRCH:
            return .alreadyExited
        case EPERM:
            return .permissionDenied
        default:
            return .failed(err)
        }
    }

    /// 强行终止（`SIGKILL`），用于响应 `SIGTERM` 失败后由用户显式确认时调用。
    static func forceKill(
        pid: Int32,
        currentPID: Int32 = getpid(),
        sendSignal: SignalSender = { Darwin.kill($0, $1) }
    ) -> Outcome {
        guard pid > 1, pid != currentPID else {
            return .protectedProcess
        }
        let result = sendSignal(pid, SIGKILL)
        if result == 0 {
            return .terminated
        }
        let err = errno
        switch err {
        case ESRCH:
            return .alreadyExited
        case EPERM:
            return .permissionDenied
        default:
            return .failed(err)
        }
    }
}
