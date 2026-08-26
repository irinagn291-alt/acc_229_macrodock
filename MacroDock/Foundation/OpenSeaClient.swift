import Foundation

struct FlexibleNumber: Decodable, Sendable, Equatable {
    let value: Double?

    init(value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            value = number
            return
        }
        if let number = try? container.decode(Int.self) {
            value = Double(number)
            return
        }
        if let text = try? container.decode(String.self) {
            value = Double(text)
            return
        }
        value = nil
    }
}

struct OpenSeaNutrimentsDTO: Decodable, Sendable {
    let energyKcal100g: FlexibleNumber?
    let energy100g: FlexibleNumber?
    let proteins100g: FlexibleNumber?
    let carbohydrates100g: FlexibleNumber?
    let fat100g: FlexibleNumber?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energy100g = "energy_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
    }
}

struct OpenSeaProductDTO: Decodable, Sendable {
    let code: String?
    let productName: String?
    let genericName: String?
    let brands: String?
    let nutriments: OpenSeaNutrimentsDTO?
    let imageFrontSmallUrl: String?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case nutriments
        case imageFrontSmallUrl = "image_front_small_url"
        case imageUrl = "image_url"
    }
}

struct OpenSeaSearchDTO: Decodable, Sendable {
    let products: [OpenSeaProductDTO]?
}

struct OpenSeaProductResponseDTO: Decodable, Sendable {
    let status: Int?
    let product: OpenSeaProductDTO?
}

enum OpenSeaMapper {
    static func domain(from dto: OpenSeaProductDTO, fallbackCode: String? = nil) -> CargoProduct? {
        let name = [dto.productName, dto.genericName, dto.brands]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name else { return nil }
        let barcode = (dto.code?.isEmpty == false ? dto.code : fallbackCode) ?? ""
        guard !barcode.isEmpty else { return nil }
        let kcal = PortionRigging.kcalPer100(
            kcal: dto.nutriments?.energyKcal100g?.value,
            kilojoules: dto.nutriments?.energy100g?.value
        )
        let imageText = dto.imageFrontSmallUrl ?? dto.imageUrl
        return CargoProduct(
            barcode: barcode,
            name: name,
            brand: dto.brands,
            kcal100: kcal,
            protein100: dto.nutriments?.proteins100g?.value,
            carbs100: dto.nutriments?.carbohydrates100g?.value,
            fat100: dto.nutriments?.fat100g?.value,
            imageURL: imageText.flatMap(URL.init(string:)),
            shelfAsset: nil,
            refreshedEpoch: Int64(Date().timeIntervalSince1970)
        )
    }
}

/// Role in MVVM-C: single networking client for Open Food Facts. Maps DTOs to domain types.
actor OpenSeaClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 15
            configuration.httpAdditionalHeaders = [
                "User-Agent": "MacroDock/1.0 (iOS; +https://macrodock.pro)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func search(terms: String) async throws -> [CargoProduct] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "28")
        ]
        guard let url = components?.url else { throw HarborFault.transport }
        let data = try await fetch(url)
        let decoded: OpenSeaSearchDTO
        do {
            decoded = try JSONDecoder().decode(OpenSeaSearchDTO.self, from: data)
        } catch {
            throw HarborFault.decoding
        }
        return (decoded.products ?? []).compactMap { OpenSeaMapper.domain(from: $0) }
    }

    func product(code: String) async throws -> CargoProduct {
        guard let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(encoded).json")
        else { throw HarborFault.transport }
        let data = try await fetch(url)
        let decoded: OpenSeaProductResponseDTO
        do {
            decoded = try JSONDecoder().decode(OpenSeaProductResponseDTO.self, from: data)
        } catch {
            throw HarborFault.decoding
        }
        if decoded.status == 0 {
            throw HarborFault.notFound
        }
        guard let productDTO = decoded.product,
              let product = OpenSeaMapper.domain(from: productDTO, fallbackCode: code)
        else {
            throw HarborFault.notFound
        }
        return product
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("MacroDock/1.0 (iOS; +https://macrodock.pro)", forHTTPHeaderField: "User-Agent")
        do {
            return try await once(request)
        } catch is CancellationError {
            throw HarborFault.cancelled
        } catch let fault as HarborFault {
            if fault == .notFound || fault == .cancelled { throw fault }
            do {
                return try await once(request)
            } catch is CancellationError {
                throw HarborFault.cancelled
            } catch {
                throw HarborFault.transport
            }
        } catch {
            do {
                return try await once(request)
            } catch is CancellationError {
                throw HarborFault.cancelled
            } catch {
                throw HarborFault.transport
            }
        }
    }

    private func once(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HarborFault.transport }
        if http.statusCode == 404 { throw HarborFault.notFound }
        guard (200..<300).contains(http.statusCode) else { throw HarborFault.transport }
        return data
    }
}
