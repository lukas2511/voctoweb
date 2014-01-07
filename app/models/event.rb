class Event < ActiveRecord::Base
  include Recent
  include FahrplanParser
  include Download

  belongs_to :conference
  has_many :recordings, dependent: :destroy

  validates_presence_of :conference
  validates_presence_of :guid
  validates_uniqueness_of :guid

  before_destroy :delete_page_file

  scope :recordings_by_mime_type, lambda { |type| joins(:recordings).where(recordings: {mime_type: type}) }

  serialize :persons, Array
  serialize :tags, Array

  # active admin and serialized fields workaround:
  attr_accessor   :persons_raw, :tags_raw

  # active admin and serialized fields workaround:
  def persons_raw
    self.persons.join("\n") unless self.persons.nil?
  end

  # active admin and serialized fields workaround:
  def persons_raw=(values)
    self.persons = []
    self.persons = values.split("\n")
  end

  # active admin and serialized fields workaround:
  def tags_raw
    self.tags.join("\n") unless self.tags.nil?
  end

  # active admin and serialized fields workaround:
  def tags_raw=(values)
    self.tags = []
    self.tags= values.split("\n")
  end

  def self.bulk_update_events(selection)
    Rails.logger.info "Bulk updating events from XML"
    # TODO fix this mess
    fahrplans = {}
    ActiveRecord::Base.transaction do
      Event.find(selection).each do |event|
        if fahrplans[conference.acronym]
          fahrplan = fahrplans[conference.acronym]
        else
          fahrplan = FahrplanParser.new(event.conference.schedule_xml)
          fahrplans[conference.acronym] = fahrplan
        end

        info = fahrplan.event_info_by_guid[event.guid]
        update_event_info(event, info)
      end
    end
  end

  def self.bulk_update_videopages(selection)
    Rails.logger.info "Bulk update videopages"
    Event.find(selection).each do |event|
      VideopageBuilder.save_videopage(event.conference, event)
    end
  end

  def get_recording_by_mime_type(type)
    self.recordings.where(mime_type: type)
  end

  def recordings_by_mime_type
    Hash[self.recordings.map { |r| [r.mime_type, r] }]
  end

  def fill_event_info
    if self.conference.downloaded?
      fahrplan = FahrplanParser.new(self.conference.schedule_xml)
      info = fahrplan.event_info_by_guid[self.guid]
      update_event_info(self, info)
    end
  end

  def set_image_filenames(thumb_url, gif_url, poster_url)
    self.thumb_filename = get_image_filename thumb_url if thumb_url
    self.gif_filename = get_image_filename gif_url if gif_url
    self.poster_filename = get_image_filename poster_url if poster_url
  end

  def download_images(thumb_url, gif_url, poster_url)
    FileUtils.mkdir_p self.conference.get_images_path
    self.delay.download_image(thumb_url, thumb_filename)
    self.delay.download_image(gif_url, gif_filename)
    self.delay.download_image(poster_url, poster_filename)
  end

  def download_image(url, filename)
    return if url.nil? or filename.nil?
    path = File.join self.conference.get_images_path, filename
    download_to_file(url, path)
  end

  def get_videopage_path
    page_file = File.join(self.conference.get_webgen_location, get_videopage_filename)
    page_file
  end

  # OBOSOLETE
  def get_videopage_filename
    if self.slug.present?
      filename = self.slug + '.page'
    else
      filename = self.guid + '.page'
    end
    filename.gsub!(/ /, '_')
    filename
  end

  def get_filename
    if self.slug.present?
      filename = self.slug
    else
      filename = self.guid
    end
    filename.gsub!(/ /, '_')
    filename
  end

  def display_name
    if self.title.present?
      self.conference.acronym + ": " + self.title 
    else
      self.guid || self.id
    end
  end


  private

  # update event attributes from schedule XML
  def update_event_info(event, info)
      event.title = info.delete(:title)
      id = info.delete(:id)
      event.link = event.conference.get_event_url(id)
      event.update_attributes info
  end

  def delete_page_file
    VideopageBuilder.remove_videopage(self.conference, self)
  end

  def get_image_filename(url)
    if url
      File.basename URI(url).path
    else
      ""
    end
  end

end
