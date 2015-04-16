require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'open3'

describe 'buildpack_packager binary' do
  def run_packager_binary
    packager_binary_file = "#{`pwd`.chomp}/bin/buildpack-packager"
    Open3.capture3("cd #{buildpack_dir} && #{packager_binary_file} #{mode}")
  end

  def create_manifest
    File.open(File.join(buildpack_dir, 'manifest.yml'), 'w') do |manifest_file|
      manifest_file.write <<-MANIFEST
---
language: sample

url_to_dependency_map:
  - match: fake_name(\d+\.\d+(\.\d+)?)
    name: fake_name
    version: $1

dependencies:
  - name: fake_name
    version: 1.2
    uri: file://#{file_location}
    md5: #{md5}
    cf_stacks:
      - lucid64
      - cflinuxfs2

exclude_files:
  - .gitignore
  - lib/ephemeral_junkpile
MANIFEST
    end

    files_to_include << 'manifest.yml'
  end

  def create_invalid_manifest
    File.open(File.join(buildpack_dir, 'manifest.yml'), 'w') do |manifest_file|
      manifest_file.write <<-MANIFEST
---
language: sample

dependencies:
  - name: fake_name
    version: 1.2
    uri: file://#{file_location}
MANIFEST
    end

    files_to_include << 'manifest.yml'
  end

  let(:tmp_dir) { Dir.mktmpdir }
  let(:buildpack_dir) { File.join(tmp_dir, 'sample-buildpack-root-dir') }
  let(:remote_dependencies_dir) { File.join(tmp_dir, 'remote_dependencies') }
  let(:file_location) { "#{remote_dependencies_dir}/dep1.txt" }
  let(:md5) { Digest::MD5.file(file_location).hexdigest }

  let(:files_to_include) {
    [
      'VERSION',
      'README.md',
      'lib/sai.to',
      'lib/rash'
    ]
  }

  let(:files_to_exclude) {
    [
      '.gitignore',
      'lib/ephemeral_junkpile'
    ]
  }

  let(:files) { files_to_include + files_to_exclude }

  let(:dependencies) {
    ['dep1.txt']
  }

  before do
    make_fake_files(
      remote_dependencies_dir,
      dependencies
    )

    make_fake_files(
      buildpack_dir,
      files
    )

    `echo "1.2.3" > #{File.join(buildpack_dir, 'VERSION')}`
  end

  after do
    FileUtils.remove_entry tmp_dir
  end

  context 'without a manifest' do
    let(:mode) { 'uncached' }

    specify do
      _, stderr, status = run_packager_binary

      expect(stderr).to include('Could not find manifest.yml')
      expect(status).not_to be_success
    end
  end

  context 'with an invalid manifest' do
    let(:mode) { 'uncached' }

    before do
      create_invalid_manifest
    end

    specify do
      _, stderr, status = run_packager_binary
      expect(stderr).to include('parser_error')
      expect(status).not_to be_success
    end
  end

  describe 'usage' do
    context 'without a mode parameter' do
      let(:mode) { "" }
      specify do
        stdout, _, status = run_packager_binary

        expect(stdout).to include("Usage:\n  buildpack-packager cached|uncached")
        expect(status).not_to be_success
      end
    end

    context 'with an invalid mode parameter' do
      let(:mode) { 'beast' }

      it 'reports proper usage' do
        stdout, _, status = run_packager_binary

        expect(stdout).to include("Usage:\n  buildpack-packager cached|uncached")
        expect(status).not_to be_success
      end
    end
  end

  context 'with a manifest' do
    before do
      create_manifest
    end

    describe 'the zip file contents' do

      context 'an uncached buildpack' do
        let(:mode) { 'uncached' }

        specify do
          stdout, stderr, status = run_packager_binary

          zip_file_path = File.join(buildpack_dir, 'sample_buildpack-v1.2.3.zip')
          zip_contents = get_zip_contents(zip_file_path)

          expect(zip_contents).to match_array(files_to_include)
          expect(status).to be_success
        end
      end

      context 'an cached buildpack' do
        let(:mode) { 'cached' }

        specify do
          stdout, stderr, status = run_packager_binary

          zip_file_path = File.join(buildpack_dir, 'sample_buildpack-cached-v1.2.3.zip')
          zip_contents = get_zip_contents(zip_file_path)

          dependencies_with_translation = dependencies.
            map { |dep| "file://#{remote_dependencies_dir}/#{dep}" }.
            map { |path| path.gsub(/[:\/]/, '_') }

            deps_with_path = dependencies_with_translation.map { |dep| "dependencies/#{dep}" }

            expect(zip_contents).to match_array(files_to_include + deps_with_path)
            expect(status).to be_success

        end

        context 'vendored dependencies with invalid checksums' do
          let(:md5) { "InvalidMD5_123" }

          specify do
            _, _, status = run_packager_binary
            expect(status).not_to be_success
          end
        end
      end
    end
  end
end