//
//  BaseResponse.swift
//  
//
//  Created  on 03.01.2020.
//  Copyright © 2020 . All rights reserved.
//

import Foundation

import Alamofire
import RxSwift

typealias Headers = [AnyHashable: Any]

public protocol RequestOutput {
    
    associatedtype T
    
    func urlRequest() async throws -> Alamofire.DataRequest
    
}

public struct ConcreteRequest<T>: RequestOutput {
    
    let x: Alamofire.DataRequest
    
    public func urlRequest() async throws -> DataRequest {
        return x
    }
    
}

public extension RequestOutput where T: Decodable {
    
    func plainResponse() async throws -> T {
        let (data, _) = try await bottleNeck()
        return try appConfig.network!.networkDecoder.decode(T.self, from: data)
    }
    
    func rxPlainResponse() -> Single<T> {
        return .fromAsync(f: plainResponse)
    }
    
}

public extension RequestOutput where T == Void {
    
    func emptyResponse() async throws -> Void {
        let _ = try await bottleNeck()
    }
    
    func emptyResponse() -> Single<Void> {
        return rxBottleNeck().map { _ in }
    }
    
}

public extension RequestOutput where T == Data {
    
    func rawResponse() async throws -> T {
        try await bottleNeck().body
    }
    
}

public extension RequestOutput {
    
    fileprivate func bottleNeck(  ) async throws -> (body: Data, headers: Headers?) {
        let request = try await urlRequest()
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                request
                    .validate()
                    .responseData(emptyResponseCodes: [200, 204, 205]) { (response: AFDataResponse<Data>) in

                        if let e = response.error {
                            
                            if let data = response.data,
                               let customError = appConfig.network?.customErrorMapper?(e, data) {
                               
                                continuation.resume(throwing: customError)
                                return;
                            }
                            
                            continuation.resume(throwing: e)
                            return
                        }
                        
                        guard let mappedResponse = response.value else {
                            fatalError("Result is not success and not error")
                        }
                        
                        continuation.resume(returning: (mappedResponse, response.response?.allHeaderFields))
                    }
            }
        } onCancel: {
            request.cancel()
        }

    }
    
    fileprivate func rxBottleNeck(  ) -> Single<(body: Data, headers: Headers?)> {
        
        Single.fromAsync(f: bottleNeck)
        
    }
    
}

public typealias Func<T, U> = (T) async throws -> U

public extension Single {
    
    static func fromAsync( f: @escaping Func<Void, Element> ) -> Single<Element> {
        
        return Single.create { (subscriber) -> Disposable in
            
            let t = Task {
                
                do {
                    let res = try await f( () )
                    await MainActor.run {
                        subscriber(.success(res))
                    }
                } catch {
                    await MainActor.run {
                        subscriber(.failure(error))
                    }
                }
                
            }
            
            return Disposables.create {
                t.cancel()
            }
        }
        
    }
    
}

