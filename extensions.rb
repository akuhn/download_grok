

class Hash
  def method_missing(name, *args)
    fetch(name.to_s) { super }
  end

  # def [](key)
  #   /\./ === key ? dig(*key.split('.')) : super
  # end
end
