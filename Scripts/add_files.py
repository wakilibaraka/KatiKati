from pbxproj import XcodeProject
project = XcodeProject.load('KatiKati.xcodeproj/project.pbxproj')

files = [
    'Core/Support/WeatherState.swift',
    'Core/Support/WeatherResponseParsing.swift',
    'App/Composition/WeatherService.swift',
    'App/Scenes/WeatherChip.swift',
]

target = project.get_target_by_name('KatiKati')

for f in files:
    project.add_file(f, target_name='KatiKati', force=False)

test_files = [
    'Tests/Unit/WeatherResponseParsingTests.swift',
]

for f in test_files:
    project.add_file(f, target_name='KatiKatiTests', force=False)

project.save()
