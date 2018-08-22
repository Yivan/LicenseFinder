require 'spec_helper'
require 'fakefs/spec_helpers'
require 'set'

module LicenseFinder
  def self.broken_fakefs?
    RUBY_PLATFORM =~ /java/ || RUBY_VERSION =~ /^(1\.9|2\.0)/
  end

  describe Dotnet do
    it_behaves_like 'a PackageManager'

    describe '.package_management_command' do
      it 'returns the correct package management command' do
        expect(described_class.package_management_command).to eq('dotnet')
      end
    end

    describe '.prepare_command' do
      it 'returns the correct prepare command' do
        expect(described_class.prepare_command).to eq('dotnet restore')
      end
    end

    describe '.prepare', skip: LicenseFinder.broken_fakefs? do
      include FakeFS::SpecHelpers
      before do
        FileUtils.mkdir_p 'app/someproj'
        FileUtils.touch 'app/someproj/someproj.csproj'
      end

      it 'calls dotnet restore' do
        dotnet = Dotnet.new project_path: Pathname.new('app')
        expect(SharedHelpers::Cmd).to receive(:run).with('dotnet restore')
                                          .and_return(['', '', cmd_success])
        dotnet.prepare
      end
    end

    describe '#current_packages', skip: LicenseFinder.broken_fakefs? do
      include FakeFS::SpecHelpers

      let(:assets_json1) do
        <<-EOF
        {
          "libraries": {
            "Thing1/5.2.6": {
              "path": "",
              "files": []
            },
            "Thing2/1.2.3": {
              "path": "",
              "files": []
            }
          }
        }
        EOF
      end

      let(:assets_json2) do
        <<-EOF
        {
          "libraries": {
            "Thing3/5.2.6": {
              "path": "",
              "files": []
            },
            "Thing2/1.2.3": {
              "path": "",
              "files": []
            }
          }
        }
        EOF
      end

      before do
        FileUtils.mkdir_p 'app/project'
        FileUtils.touch 'app/project/project1.csproj'
        FileUtils.mkdir_p 'app/project1/obj'
        FileUtils.mkdir_p 'app/project2/obj'
        File.write('app/project1/obj/project.assets.json', assets_json1)
        File.write('app/project2/obj/project.assets.json', assets_json2)
      end

      it 'lists all the packages used in a project' do
        dotnet = Dotnet.new project_path: Pathname.new('app')
        actual = dotnet.current_packages

        expect(actual.map(&:name)).to match_array ['Thing1', 'Thing2', 'Thing3']
        expect(actual.map(&:version)).to match_array ['5.2.6', '1.2.3', '5.2.6']
      end

      describe 'When a package has a license URL' do
        let(:assets_json1) do
          <<-EOF
          {
            "libraries": {
              "Thing1/5.2.6": {
                "path": "thing1 path/5.2.6",
                "files": [
                  "not a nuspec",
                  "thing1 spec.nuspec"
                ]
              }
            },
            "packageFolders": {
              "packages1": {},
              "packages2": {}
            }
          }
          EOF
        end

        let(:assets_json2) do
          <<-EOF
          {
            "libraries": {}
          }
          EOF
        end

        let(:thing1_spec) do
          <<-EOF
          <?xml version="1.0" encoding="utf-8"?>
          <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
            <metadata minClientVersion="3.6">
              <licenseUrl>https://example.com</licenseUrl>
            </metadata>
          </package>
          EOF
        end

        before do
          FileUtils.mkdir_p('packages1')
          FileUtils.mkdir_p('packages2/thing1 path/5.2.6/')
          File.write('packages2/thing1 path/5.2.6/thing1 spec.nuspec', thing1_spec)
        end

        it 'uses the license URL as the license' do
          dotnet = Dotnet.new project_path: Pathname.new('app')
          licenses = dotnet.current_packages[0].license_names_from_spec

          expect(licenses).to eq(['https://example.com'])
        end
      end
    end
  end

  describe Dotnet::AssetFile do
    describe '#packages', skip: LicenseFinder.broken_fakefs? do
      include FakeFS::SpecHelpers

      let(:assets_json) do
        <<-EOF
        {
          "version": 3,
          "libraries": {
            "Thing1/5.2.6": {
              "path": "thing1/5.2.6",
              "files": ["foo.nuspec"]
            },
            "Thing2/1.2.3": {
              "path": "thing1/5.2.6",
              "files": ["foo"]
            }
          },
          "packageFolders": {
            "packageFolder1": {},
            "packageFolder2": {}
          }
        }
        EOF
      end

      before do
        File.write('project.assets.json', assets_json)
      end

      it 'returns the list of packages' do
        assetFile = Dotnet::AssetFile.new('project.assets.json')
        actual = assetFile.dependencies
        expected = [
            Dotnet::PackageMetadata.new(
                'Thing1',
                '5.2.6',
                [
                    'packageFolder1/thing1/5.2.6/foo.nuspec',
                    'packageFolder2/thing1/5.2.6/foo.nuspec'
                ]),
            Dotnet::PackageMetadata.new('Thing2', '1.2.3', []),
        ]
        expect(actual).to eq(expected)
      end
    end
  end
end