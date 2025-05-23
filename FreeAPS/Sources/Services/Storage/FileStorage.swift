import Foundation

protocol FileStorage {
    func save<Value: JSON>(_ value: Value, as name: String)
    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value?
    func retrieveRaw(_ name: String) -> RawJSON?
    func retrieveRawAsync(_ name: String) async -> RawJSON?
    func append<Value: JSON>(_ newValue: Value, to name: String)
    func append<Value: JSON>(_ newValues: [Value], to name: String)
    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>)
    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>)
    func remove(_ name: String)
    func rename(_ name: String, to newName: String)
    func transaction(_ exec: (FileStorage) -> Void)
    func retrieveFile<Value: JSON>(_ name: String, as type: Value.Type) -> Value?

    func urlFor(file: String) -> URL?
}

final class BaseFileStorage: FileStorage, Injectable {
    private let processQueue = DispatchQueue.markedQueue(
        label: "BaseFileStorage.processQueue",
        qos: .utility
    )

    private var fileQueues: [String: DispatchQueue] = [:]
    private let queueAccessLock = DispatchQueue(label: "BaseFileStorage.processQueue")

    private func getQueue(for path: String) -> DispatchQueue {
        queueAccessLock.sync {
            if let queue = fileQueues[path] {
                return queue
            } else {
                let newQueue = DispatchQueue(label: "BaseFileStorage.processQueue.\(path.hashValue)", qos: .utility)
                fileQueues[path] = newQueue
                return newQueue
            }
        }
    }

    func save<Value: JSON>(_ value: Value, as name: String) {
        getQueue(for: name).sync {
            if let value = value as? RawJSON, let data = value.data(using: .utf8) {
                try? Disk.save(data, to: .documents, as: name)
            } else {
                try? Disk.save(value, to: .documents, as: name, encoder: JSONCoding.encoder)
            }
        }
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        getQueue(for: name).sync {
            try? Disk.retrieve(name, from: .documents, as: type, decoder: JSONCoding.decoder)
        }
    }

    func retrieveRaw(_ name: String) -> RawJSON? {
        getQueue(for: name).sync {
            guard let data = try? Disk.retrieve(name, from: .documents, as: Data.self) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }

    func retrieveRawAsync(_ name: String) async -> RawJSON? {
        await withCheckedContinuation { continuation in
            getQueue(for: name).async {
                guard let data = try? Disk.retrieve(name, from: .documents, as: Data.self) else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = String(data: data, encoding: .utf8)
                continuation.resume(returning: result)
            }
        }
    }

    func retrieveFile<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        if let loaded = retrieve(name, as: type) {
            return loaded
        }
        let file = retrieveRaw(name) ?? OpenAPS.defaults(for: name)
        save(file, as: name)
        return retrieve(name, as: type)
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) {
        getQueue(for: name).sync {
            try? Disk.append(newValue, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
        }
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) {
        getQueue(for: name).sync {
            try? Disk.append(newValues, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        if let value = retrieve(name, as: Value.self) {
            if value[keyPath: keyPath] != newValue[keyPath: keyPath] {
                append(newValue, to: name)
            }
        } else if let values = retrieve(name, as: [Value].self) {
            guard values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil else {
                return
            }
            append(newValue, to: name)
        } else {
            save(newValue, as: name)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        if let value = retrieve(name, as: Value.self) {
            if newValues.firstIndex(where: { $0[keyPath: keyPath] == value[keyPath: keyPath] }) != nil {
                save(newValues, as: name)
                return
            }
            append(newValues, to: name)
        } else if var values = retrieve(name, as: [Value].self) {
            for newValue in newValues {
                if let index = values.firstIndex(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) {
                    values[index] = newValue
                } else {
                    values.append(newValue)
                }
                save(values, as: name)
            }
        } else {
            save(newValues, as: name)
        }
    }

    func remove(_ name: String) {
        getQueue(for: name).sync {
            try? Disk.remove(name, from: .documents)
        }
    }

    func rename(_ name: String, to newName: String) {
        getQueue(for: name).sync {
            try? Disk.rename(name, in: .documents, to: newName)
        }
    }

    func transaction(_ exec: (FileStorage) -> Void) {
        processQueue.safeSync {
            exec(self)
        }
    }

    func urlFor(file: String) -> URL? {
        try? Disk.url(for: file, in: .documents)
    }
}
