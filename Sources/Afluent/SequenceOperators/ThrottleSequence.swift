//
//  ThrottleSequence.swift
//
//
//  Created by Trip Phillips on 2/12/24.
//

import Foundation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncSequences {
    public struct Throttle<Upstream: AsyncSequence, C: Clock>: AsyncSequence {
        public typealias Element = Upstream.Element
        let upstream: Upstream
        let interval: C.Duration
        let clock: C
        let latest: Bool
        
        public struct AsyncIterator: AsyncIteratorProtocol {
            typealias Instant = C.Instant
            
            let upstream: Upstream
            let interval: C.Duration
            var iterator: AsyncThrowingStream<(Instant, Element), Error>.Iterator
            let clock: C
            let latest: Bool
            
            private var firstIntervalInstant: C.Instant?
            private var firstElement: Element?
            private var lastElement: Element?
            
            init(upstream: Upstream,
                 interval: C.Duration,
                 clock: C,
                 latest: Bool) {
                self.upstream = upstream
                self.interval = interval
                self.clock = clock
                self.latest = latest
                
                let stream = AsyncThrowingStream<(Instant, Element), Error> { continuation in
                    Task {
                        do {
                            for try await el in upstream {
                                let time = clock.now
                                continuation.yield((time, el))
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
                iterator = stream.makeAsyncIterator()
            }
            
            public mutating func next() async throws -> Element? {
                try Task.checkCancellation()
                
                while let (instant, element) = try await iterator.next() {
                    if let firstIntervalInstant {
                        let timeSinceFirstInstant = firstIntervalInstant.duration(to: instant)
                        if firstElement == nil {
                            firstElement = element
                        }
                        
                        lastElement = element
                        
                        if timeSinceFirstInstant >= interval {
                            defer {
                                self.firstIntervalInstant = nil
                                firstElement = nil
                            }
                            self.firstIntervalInstant = instant
                            return latest ? lastElement : firstElement
                        } else {
                            continue
                        }
                    } else {
                        firstIntervalInstant = instant
                        return element
                    }
                }
                return nil
            }
        }
        
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(upstream: upstream, interval: interval, clock: clock, latest: latest)
        }
    }
}

@available(iOS 16.0, *)
extension AsyncSequence {
    public func throttle<C: Clock>(for interval: C.Duration, clock: C, latest: Bool = false) -> AsyncSequences.Throttle<Self, C> {
        AsyncSequences.Throttle(upstream: self, interval: interval, clock: clock, latest: latest)
    }
}