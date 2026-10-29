import Foundation

let manager = ExceptionManager()
manager.start()

let delegate = HelperListenerDelegate(manager: manager)
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

withExtendedLifetime(delegate) {
    RunLoop.current.run()
}
