Pod::Spec.new do |s|
  s.name             = 'OpentelemetrySwift'
  s.version          = '1.9.1'
  s.summary          = 'High-quality, ubiquitous, and portable telemetry to enable effective observability'

  s.homepage         = 'https://opentelemetry.io'
  s.license          = { :type => 'Apache', :file => 'LICENSE' }
  s.author           = {
     'Bryce Buchanan' => 'bryce.buchanan@elastic.co',
     'Pavel Aliferka' => 'pavel.aliferka@elastic.co'
  }

# Source Info
  s.ios.deployment_target = '13.0'
  s.source          =  {
    :git => '"https://github.com/open-telemetry/opentelemetry-swift.git',
    :tag => 'v'+s.version.to_s
  }

  s.source_files    = 'Sources/**/*.swift'

#  s.requires_arc   = true
  s.swift_version   = '5.7'

# Dependencies
  s.dependency = 'opentracing', '~>0.5.2'
  s.dependency = 'Thrift-swift3', '~>1.1.1'
  s.dependency = 'SwiftNIO', '~>2.0.0'
  s.dependency = 'gRPC-Swift', '~>1.0.0'
  s.dependency = 'SwiftProtobuf', '~>1.20.2'
  s.dependency = 'Logging', '~>1.4.4'
  s.dependency = 'SwiftMetrics', '~>2.1.1'

end
