//
//  ImageRetreiver.swift
//
//
//  Created  on 04.01.2020.
//  Copyright © 2020. All rights reserved.
//

import UIKit
import MapKit

import RxSwift
import Kingfisher

public extension Reactive where Base: UIImageView {
    
    func download(url: String?, size: CGSize? = nil, placeholder: UIImage? = nil) -> Observable<Void> {
        
        return Observable<Void>.create { (subscriber) -> Disposable in

            var options: KingfisherOptionsInfo = [
                .onFailureImage(placeholder)
            ]
            
            if let x = size {
                options.append( .processor( DownsamplingImageProcessor(size: x) ) )
            }
            
            options.append(.requestModifier(TokenPlugin()))
            
            guard let str = url, let url = URL(string: str) else {
                self.base.image = placeholder
                subscriber.onCompleted()
                return Disposables.create()
            }
            
            var wasCanceled = false
            
            let task = self.base.kf
                .setImage(with: url,
                          placeholder: placeholder,
                          options: options,
                          completionHandler: { (error) in
                            
//                            if case .failure(let e) = error { print("Failed downloading image \(e)") }
                            
                            ///kingsfisher acts weird when canceling task
                            ///reports some network error instead of
                            ///error that task was canceled
                            if wasCanceled { return }
                            
                            subscriber.onCompleted()
                          })
            
            return Disposables.create {
                wasCanceled = true
                task?.cancel()
            }
        }
    }
    
}

class TokenPlugin: AsyncImageDownloadRequestModifier {
    var onDownloadTaskStarted: ((Kingfisher.DownloadTask?) -> Void)?
    
    func modified(for request: URLRequest, reportModified: @escaping (URLRequest?) -> Void) {
        guard let auth = appConfig.network?.authRequestHeaders else {
            return reportModified(request)
        }
        
        Task {
            var request = request
            var headers: [String: String] = [:]
            await auth(&headers)
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
            reportModified(request)
        }
        
    }

}

public extension Reactive where Base: UIImageView {
    
    func map(around coordinate: CLLocationCoordinate2D, placeholder: UIImage? = nil) -> Observable<Void> {
        
        return Observable<Void>.create { (subscriber) -> Disposable in

            if let i = ImageCache.default.retrieveImageInMemoryCache(forKey: coordinate.cacheKey) {
                self.base.image = i
                subscriber.onCompleted()
                return Disposables.create()
            }
            
            let options = MKMapSnapshotter.Options.init()
            options.region = .init(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            options.scale = 1.0
            options.size = .init(width: 250, height: 250)
            options.mapType = .standard
            
            let snapshotter = MKMapSnapshotter(options: options)
            
            var wasCanceled = false
            
            snapshotter.start { (snapshot, error) in
                
                guard let image = snapshot?.image else {
                    if wasCanceled { return }
                    subscriber.onCompleted()
                    return;
                }
                
                ImageCache.default.store(image, forKey: coordinate.cacheKey, toDisk: false)
                base.image = image
                if wasCanceled { return }
                subscriber.onCompleted()
                
                
            }
            
            return Disposables.create {
                wasCanceled = true
                snapshotter.cancel()
            }
        }
    }
    
}

public extension CLLocationCoordinate2D {
    var cacheKey: String {
        String(format: "%.5f;", latitude) +
        String(format: "%.5f", longitude)
    }
}


public extension UIImage {
    
    func cache(for key: String) {
        KingfisherManager.shared.cache.store(self, forKey: key)
    }
    
    static func removeFromCache(key: String) {
        KingfisherManager.shared.cache.removeImage(forKey: key)
    }
    
}
