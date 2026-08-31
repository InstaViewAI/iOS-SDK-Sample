# Sandbox sample app — single target, single partner.
use_frameworks!
platform :ios, '15.5'

target 'Sandbox' do
  # Auth providers used by the SDK's signin/signup entry points.
  pod 'Firebase'
  pod 'FirebaseAuth'
  pod 'GoogleSignIn'

  # FFmpeg-based player for event playback. AVFoundation cannot decode HEVC
  # inside MPEG-TS segments, which is what these cameras record.
  pod 'IJKMediaFrameworkWithSSL', '~> 0.0.3'

  # The home-security SDK.
  pod 'IVSDK', :git => 'https://github.com/InstaViewAI/IVSDK-iOS', :tag => '3.0.1'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] ||= '$(inherited)'
    end
  end
end
