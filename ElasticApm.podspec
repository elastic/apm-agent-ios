Pod::Spec.new do |s|
  s.name             = 'ElasticApm'
  s.version          = '1.0.2'
  s.summary          = 'Official Elastic APM agent for iOS native apps'

  s.homepage         = 'https://www.elastic.co/solutions/apm'
  s.license          = { :type => 'Apache', :file => 'LICENSE' }
  s.author           = {
     'Bryce Buchanan' => 'bryce.buchanan@elastic.co',
     'Pavel Aliferka' => 'pavel.aliferka@elastic.co'
  }

# Source Info
  s.ios.deployment_target = '13.0'
  s.source          =  {
    :git => 'https://github.com/elastic/apm-agent-ios.git',
    :tag => 'v'+s.version.to_s
  }

  s.source_files    = 'Sources/apm-agent-ios/**/*.swift'
  s.resource_bundle = {"apm-agent-ios" => "Sources/apm-agent-ios/Resources/PrivacyInfo.xcprivacy"}

#  s.requires_arc   = true
  s.swift_version   = '5.7'

# Dependencies
  s.dependency = 'Kronos', '~>4.2.2'
  s.dependency = 'plcrashreporter', '~>1.0.0'
  s.dependency = 'Reachability', '~>5.2.0'

end
